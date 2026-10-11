#!/usr/bin/env python3
"""Bounded macOS candidate gates. This script never executes official references.

Native receipts distinguish CommandResult UTF8 from original raw process bytes.
The enclosing SwiftPM process owns a fresh SID; retain failure artifacts, and
stop after any incomplete or failed stage. No skip-build or parallel gates.
"""
from pathlib import Path
import argparse, hashlib, json, os, platform, re, signal, subprocess, time

def sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):digest.update(block)
    return digest.hexdigest()

def snapshots(root):
    return {str(p.relative_to(root)):sha(p) for base in ('Sources','Tests','Scripts')
            for p in sorted((root/base).rglob('*')) if p.is_file()
            and '__pycache__' not in p.parts}

def products(root):
    debug=root/'.build'/'debug'
    selected=[]
    compiler=debug/'kswiftc'
    if compiler.is_file(): selected.append(compiler)
    for binary in debug.glob('*Tests.xctest'):
        if binary.is_file(): selected.append(binary)
        elif binary.is_dir(): selected.extend(p for p in binary.rglob('*') if p.is_file())
    return {str(p.relative_to(root)):{'sha256':sha(p),'bytes':p.stat().st_size}
            for p in sorted(selected)}

def processes(sid):
    raw=subprocess.check_output(['ps','-axo','pid,ppid,pgid,state'],text=True)
    result=[]
    for line in raw.splitlines()[1:]:
        fields=line.split()
        if len(fields)!=4:continue
        try:
            pid=int(fields[0])
            observed=os.getsid(pid)
        except (ValueError,ProcessLookupError,PermissionError):continue
        if observed==sid:
            entry=dict(zip(('pid','ppid','pgid','state'),fields));entry['sid']=observed
            result.append(entry)
    return result

def terminate_owned_session(sid, worker):
    # Recheck the owned SID before each signal; never target unrelated groups.
    for sig in (signal.SIGTERM, signal.SIGKILL):
        owned=processes(sid)
        live=[p for p in owned if not p['state'].startswith('Z')]
        for group in {int(p['pgid']) for p in live}:
            try:os.killpg(group,sig)
            except ProcessLookupError:pass
        until=time.monotonic()+10
        while time.monotonic()<until:
            if worker.poll() is not None and not any(
                    not p['state'].startswith('Z') for p in processes(sid)):break
            time.sleep(0.2)
    # Popen owns this direct child and can reap it; PID1-owned zombies are
    # recorded separately rather than relabeled as executing workers.
    if worker.poll() is None:worker.wait(timeout=10)
    else:worker.wait(timeout=1)

def execute(argv, seconds, prefix, cwd):
    start=time.time();deadline=time.monotonic()+seconds
    worker=None;original_error=None
    receipt={'argv':argv,'start_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(start)),
             'deadline_seconds':seconds,'actual_exit':None,'status':'LAUNCHING',
             'pid':None,'sid':None,'pgid':None}
    prefix.with_suffix('.json').write_text(json.dumps(receipt,indent=2)+'\n')
    with prefix.with_suffix('.stdout').open('wb') as out, prefix.with_suffix('.stderr').open('wb') as err:
        try:
            worker=subprocess.Popen(argv,cwd=cwd,stdout=out,stderr=err,start_new_session=True)
            # start_new_session establishes SID/PGID=PID before Popen returns.
            # Do not race os.getsid against a launcher that has already exited.
            receipt.update(pid=worker.pid,sid=worker.pid,pgid=worker.pid,status='RUNNING')
            prefix.with_suffix('.json').write_text(json.dumps(receipt,indent=2)+'\n')
            while worker.poll() is None and time.monotonic()<deadline:time.sleep(5)
            receipt['status']='TIMEOUT_INCOMPLETE' if worker.poll() is None else 'PROCESS_EXITED'
        except BaseException as error:
            original_error=error
            receipt['status']='EXECUTION_EXCEPTION_INCOMPLETE'
            receipt['execution_exception']={'type':type(error).__name__,'message':str(error)}
        finally:
            receipt['cleanup_errors']=[]
            if worker is not None:
                try:
                    owned=processes(worker.pid)
                    live=[p for p in owned if not p['state'].startswith('Z')]
                    if worker.poll() is None or live:
                        if receipt['status']=='PROCESS_EXITED':
                            receipt['status']='CHILDREN_AFTER_LAUNCHER_EXIT_INCOMPLETE'
                            receipt['orphaned_at_launcher_exit']=owned
                        terminate_owned_session(worker.pid,worker)
                    else:worker.wait(timeout=1)
                except BaseException as error:
                    receipt['cleanup_errors'].append({'type':type(error).__name__,'message':str(error)})
                receipt['actual_exit']=worker.returncode
    receipt.update(elapsed_seconds=time.time()-start,
                   end_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
                   stdout_sha256=sha(prefix.with_suffix('.stdout')),
                   stderr_sha256=sha(prefix.with_suffix('.stderr')))
    try:owned=processes(worker.pid) if worker is not None else []
    except BaseException as error:
        owned=[]
        receipt['cleanup_errors'].append({'type':type(error).__name__,'message':str(error)})
    receipt['remaining_own_session']=owned
    receipt['remaining_live_own_session']=[p for p in owned if not p['state'].startswith('Z')]
    receipt['remaining_zombies']=[p for p in owned if p['state'].startswith('Z')]
    if receipt['cleanup_errors']:receipt['status']='CLEANUP_PROOF_INCOMPLETE'
    prefix.with_suffix('.json').write_text(json.dumps(receipt,indent=2)+'\n')
    if original_error is not None:raise original_error
    if receipt['status']!='PROCESS_EXITED' or receipt['actual_exit']!=0 or receipt['remaining_live_own_session']:
        raise RuntimeError(f'Gate incomplete/failed/unreaped: {prefix}; {receipt}')
    return receipt

def testing_counts(log, expected_methods):
    # Swift Testing counts methods in its final summary. Case counts come from
    # successful method lines; XCTest's zero-test launcher summary is irrelevant.
    summaries=re.findall(r'✔ Test run with (\d+) tests? in (\d+) suites? passed after ([0-9.]+) seconds',log)
    if len(summaries)!=1:
        raise RuntimeError(f'Expected exactly one observed Swift Testing PASS summary, got {summaries}')
    lines=re.findall(r'^✔ Test (?!run with )([^\n]+?) passed after [0-9.]+ seconds\.$',log,re.MULTILINE)
    methods={}
    for line in lines:
        name=line.split('(')[0].strip()
        match=re.search(r' with (\d+) test cases?$',line)
        if name in methods: raise RuntimeError(f'Duplicate successful method: {name}')
        methods[name]=int(match.group(1)) if match else 1
    observed_methods, observed_suites, elapsed=summaries[0]
    if methods!=expected_methods or int(observed_methods)!=len(expected_methods) or int(observed_suites)!=1:
        raise RuntimeError(f'Incomplete/extra scope: successful methods={methods}, summary={summaries[0]}, required={expected_methods}')
    return {'methods':len(methods),'cases':sum(methods.values()),'suites':1,
            'duration_seconds':float(elapsed),'successful_methods_and_cases':methods,
            'Swift_Testing_final_summary':summaries[0]}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--receipts',type=Path,required=True)
    args=parser.parse_args()
    if platform.system()!='Darwin':raise RuntimeError('Actual Foundation SDK macOS execution required; no Linux substitute')
    root=Path(__file__).resolve().parents[3]
    output=args.receipts.resolve();output.mkdir(parents=True,exist_ok=True)
    before=snapshots(root)
    (output/'inputs.before.json').write_text(json.dumps(before,indent=2)+'\n')
    stages=[
        ('metadata','IOAppleAPIContractTests',1200,{
            'sixAppleExtensionsHaveRealTypedPublicSourceAndImportedShapes':2}),
        ('runtime','RuntimeAppleFoundationTests',900,{
            'realNSDataCopiesAndItsLeaseFollowsBoxRelease':1,
            'nativeByteStorageSeesKotlinWritesAndPointerWrites':1,
            'nativeNoCopyStorageAndUnattachedRollbackFollowSDKOwnership':1,
            'actualNSErrorUserInfoKeepsOriginalKotlinCauseIdentity':1}),
        ('native','IOAppleInteropExecutionTests',3600,{
            'unchangedOriginal25BodiesUseActualFoundation':4,
            'unchangedOriginal25BodiesSurviveRealProducerImport':2,
            'publicOnlyCopiedSDKObjectsAndStreamLifecycles':4,
            'publicOnlySDKObjectsCrossIndependentProducerConsumer':2}),
    ]
    (output/'scope.json').write_text(json.dumps({'original_ids':25,'required_original_lanes':6,
       'expected_original_executions':150,'public_producer_consumer_lanes':2,
       'expected_methods':9,'expected_cases':18,'source_and_imported':True,
       'candidate_scope':'six Apple IO APIs; not entire Foundation or Atomicfu',
       'all_required_receipts_must_be_audited':True},indent=2)+'\n')

    all_counts={}
    terminal={'status':'RUNNING','current_stage':'build','completed_stages':[],'failure':None}
    (output/'terminal.json').write_text(json.dumps(terminal,indent=2)+'\n')
    try:
        execute(['swift','build','-j','4'],300,output/'build',root)
        (output/'build.products.json').write_text(json.dumps(products(root),indent=2)+'\n')
        terminal['completed_stages'].append('build')
        for name,pattern,limit,expected_methods in stages:
            terminal['current_stage']=name
            (output/'terminal.json').write_text(json.dumps(terminal,indent=2)+'\n')
            execute(['bash','Scripts/swift_test.sh','--no-parallel','-j','4','--filter',pattern],limit,output/name,root)
            log=(output/(name+'.stdout')).read_text(errors='replace')+(output/(name+'.stderr')).read_text(errors='replace')
            if pattern not in log:raise RuntimeError(f'{name}: selected suite missing')
            counts=testing_counts(log,expected_methods)
            (output/(name+'.test-counts.json')).write_text(json.dumps(counts,indent=2)+'\n')
            all_counts[name]=counts
            (output/(name+'.products.json')).write_text(json.dumps(products(root),indent=2)+'\n')
            if snapshots(root)!=before:raise RuntimeError('Frozen input changed')
            terminal['completed_stages'].append(name)
        terminal['status']='ALL_REQUESTED_STAGES_PASSED_PENDING_EVIDENCE_AUDIT'
    except BaseException as error:
        terminal['status']='FAILED_OR_INCOMPLETE_NOT_PASS'
        terminal['failure']={'type':type(error).__name__,'message':str(error)}
        raise
    finally:
        # Persist each available proof independently; a failed product hash must
        # neither skip inputs-after nor replace the original execution error.
        capture_errors=[]
        for filename,capture in [
            ('inputs.after.json',lambda:snapshots(root)),
            ('products.after.json',lambda:products(root)),
            ('all.test-counts.json',lambda:all_counts),
            ('retained-artifact-manifest.json',lambda:{
                str(p.relative_to(output)):{'sha256':sha(p),'bytes':p.stat().st_size}
                for p in sorted(output.rglob('*')) if p.is_file()
                and p.name not in {'retained-artifact-manifest.json','terminal.json'}}),
        ]:
            try:
                value=capture()
                (output/filename).write_text(json.dumps(value,indent=2)+'\n')
                if filename=='inputs.after.json': terminal['frozen_inputs_unchanged']=(value==before)
            except BaseException as error:
                capture_errors.append({'file':filename,'type':type(error).__name__,'message':str(error)})
        terminal['proof_capture_errors']=capture_errors
        if capture_errors or terminal.get('frozen_inputs_unchanged') is not True:
            terminal['status']='FAILED_OR_INCOMPLETE_NOT_PASS'
        (output/'terminal.json').write_text(json.dumps(terminal,indent=2)+'\n')
    if terminal['status']!='ALL_REQUESTED_STAGES_PASSED_PENDING_EVIDENCE_AUDIT':
        raise RuntimeError(f'Final evidence incomplete: {terminal}')

if __name__=='__main__':main()
