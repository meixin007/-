from pathlib import Path
import argparse,hashlib,json,os,re,statistics,subprocess,time
from windows_process_monitor import Monitor
from build_review_release import BUILD
ROOT=Path(__file__).resolve().parents[1];REPORT=ROOT/'review-work/native'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def rotate(p):
    if p.exists():raise RuntimeError('Fresh reports only: '+str(p))
def release(mode,build_id=BUILD):
    release=ROOT/'review-work/releases'/build_id;name='TongguanAuthoring' if mode=='authoring' else 'TongguanFinal';exe=release/'Windows'/(name+'.exe')
    target=REPORT/'release'/mode;target.mkdir(parents=True,exist_ok=True);out=target/'result.json';log=target/'runtime.log';rotate(out);rotate(log)
    inventory=subprocess.run(['powershell.exe','-NoProfile','-Command',"@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot|Tongguan' } | Select-Object ProcessId,Name,ExecutablePath,CommandLine) | ConvertTo-Json -Depth 3"],capture_output=True,timeout=15)
    (target/'processes_before.raw').write_bytes(inventory.stdout)
    inventory_text=inventory.stdout.decode('utf-8-sig',errors='replace').strip()
    inventory_value=json.loads(inventory_text) if inventory_text else []
    save(target/'processes_before.json',inventory_value if isinstance(inventory_value,list) else [inventory_value])
    cmd=[str(exe),'--log-file',str(log),'--','--acceptance','--expect-release','--mode='+mode,'--report='+str(out)]
    start=time.monotonic();p=subprocess.Popen(cmd,cwd=exe.parent,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);monitor=Monitor(p.pid);samples=[];cycles=[];seen=set();ready=None;last_gpu=-1;timeout=False
    try:
        while p.poll() is None:
            elapsed=time.monotonic()-start
            if elapsed>(420 if mode=='soak' else 180):timeout=True;p.kill();break
            sample=monitor.memory()
            if sample:
                sample['elapsed_s']=elapsed
                if int(elapsed)!=last_gpu:sample['gpu_dedicated_bytes']=monitor.gpu();last_gpu=int(elapsed)
                samples.append(sample)
            text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else ''
            if ready is None and 'R5_READY ' in text:ready=elapsed*1000
            for match in re.finditer(r'R5_CYCLE (\{[^\n]+\})',text):
                event=json.loads(match.group(1))
                # Release file logging is buffered. The read time is not the
                # cycle-exit time; never attach that instant's RAM to an exit.
                if event['cycle'] not in seen:seen.add(event['cycle']);cycles.append(dict(**event,log_observed_s=elapsed))
            time.sleep(.05)
        p.wait(timeout=5)
    finally:monitor.close()
    text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else ''
    diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
    result=read(out) if out.exists() else dict(failures=['no fresh result']);gpu=[s['gpu_dedicated_bytes'] for s in samples if s.get('gpu_dedicated_bytes') is not None]
    metrics=dict(pid=p.pid,process_start_to_ready_upper_bound_ms=ready,sampling_interval_target_ms=50,sampled_private_peak_bytes=max((s['private_bytes'] for s in samples),default=0),sampled_gpu_dedicated_peak_bytes=max(gpu) if gpu else None,cycle_exit_samples=cycles)
    if len(cycles)==20:
        duration=samples[-1]['elapsed_s'];initial=[s['private_bytes'] for s in samples if duration*.25<=s['elapsed_s']<=duration*.55];late=[s['private_bytes'] for s in samples if duration*.75<=s['elapsed_s']<=duration-.1]
        metrics['memory_comparison_windows_seconds']={'initial':[duration*.25,duration*.55],'final':[duration*.75,duration-.1]}
        metrics['memory_sample_counts']={'initial':len(initial),'final':len(late)}
        metrics['post_warmup_private_growth_bytes']=statistics.median(late)-statistics.median(initial)
        metrics['cycle_event_memory_note']='Release log is buffered. Cycle events prove 20 exits and cache counts; RAM comparison uses continuously sampled Windows-process windows, not log read times.'
    result.update(build_id=build_id,artifacts={p.name:sha(p) for p in (release/'Windows').iterdir() if p.is_file()},release_sha256=sha(release/'RELEASE.json'),exit_code=p.returncode,timed_out=timeout,diagnostics=diagnostics,command=cmd,windows_process_metrics=metrics)
    budgets=dict(frame_p95_ms=16.7,frame_p99_ms=25,private_bytes=4*1024**3,gpu_dedicated_bytes=1536*1024**2,cycle_private_growth_bytes=16*1024**2,scope='current PC, final prototype; configured viewport1920x1080, actual client image dimensions recorded separately; GL Compatibility')
    result['budgets']=budgets
    execution=p.returncode==0 and not timeout and not diagnostics and not result.get('failures')
    budget=metrics['sampled_private_peak_bytes']<=budgets['private_bytes'] and (not gpu or max(gpu)<=budgets['gpu_dedicated_bytes'])
    if mode in ['performance','soak']:
        budget=budget and result.get('duration_seconds',0)>=(60 if mode=='performance' else 300) and result.get('frame_p95_ms',999)<=16.7 and result.get('frame_p99_ms',999)<=25
    if mode=='cycles':budget=budget and len(cycles)==20 and metrics.get('post_warmup_private_growth_bytes',10**12)<=budgets['cycle_private_growth_bytes']
    if mode=='load':budget=budget and bool(result.get('all_display_budgets_passed',False))
    result['execution_passed']=bool(execution);result['budget_passed']=bool(budget);result['passed']=bool(execution and budget)
    save(out,result);save(target/'process_samples.json',samples)
    print('REVIEW_RELEASE',mode,'execution',execution,'budget',budget,{k:result.get(k) for k in ['checks','frame_p95_ms','frame_p99_ms','failures','diagnostics']},flush=True)
    return result['passed']

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--mode',required=True,choices=['authoring','verify','tree_edges','performance','soak','cycles','load']);a=p.parse_args();raise SystemExit(0 if release(a.mode) else 1)
