"""Owned-process native runner: untrimmed frame CSV, WDDM VRAM and private bytes."""
import argparse,csv,json,re,subprocess,time
from pathlib import Path
import numpy as np
from PIL import Image
from common import ROOT,read,save,sha
from q1_monitor import Observer
from q1_evidence import frame_summary,memory_summary

def run(build_id,run_id,mode='performance',seconds=60,warmup=10,extra=None,exe=None):
    work=ROOT/'review-work/map_v02'/build_id;clean=work/'CLEAN_WINDOWS';out=work/run_id;out.mkdir(parents=True,exist_ok=False)
    target=Path(exe) if exe else clean/'TongguanQ1.exe'
    if (target.parent/'.godot').exists() or (target.parent/'project.godot').exists():raise RuntimeError('runtime not clean')
    command=[str(target),'--fullscreen','--log-file',str(out/'runtime.log'),'--','--q1='+mode,'--report='+str(out/'engine_result.json'),'--seconds='+str(seconds),'--warmup='+str(warmup),*(extra or [])]
    before=time.monotonic_ns();process=subprocess.Popen(command,cwd=target.parent,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    observer=Observer(process.pid);samples=[];timeout=False;last_sample=0;start=time.monotonic();limit=seconds+warmup+100 if mode=='performance' else 850
    with (out/'process_samples.jsonl').open('x',encoding='utf-8') as sample_file:
        while True:
            now=time.monotonic()
            if now-last_sample>=.5:
                row=observer.sample();row['since_popen_sec']=(row['monotonic_ns']-before)/1e9
                if (out/'progress.json').exists():
                    try:row['engine_progress_last_observed']=read(out/'progress.json')
                    except (OSError,ValueError):row['engine_progress_last_observed']=None
                samples.append(row);sample_file.write(json.dumps(row)+'\n');sample_file.flush();last_sample=now
            try:stdout,stderr=process.communicate(timeout=.1);break
            except subprocess.TimeoutExpired:
                if time.monotonic()-start>limit:process.kill();stdout,stderr=process.communicate();timeout=True;break
    (out/'console.txt').write_bytes(stdout+stderr)
    log=out/'runtime.log';text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else (stdout+stderr).decode('utf-8',errors='replace');(out/'runtime.txt').write_text(text,encoding='utf-8')
    diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
    value=read(out/'engine_result.json') if (out/'engine_result.json').exists() else dict(failures=['missing engine result'])
    gpu=[]
    for pair in value.get('gpu_comparisons',[]):
        x,y,w,h=pair['roi'];a=np.asarray(Image.open(out/pair['a']).convert('RGB'))[y:y+h,x:x+w].astype(np.int16);b=np.asarray(Image.open(out/pair['b']).convert('RGB'))[y:y+h,x:x+w].astype(np.int16)
        delta=np.abs(a-b);maximum=int(delta.max());okay=(maximum<=pair['frozen_max_channel_delta'])==pair['expect_equal'];gpu.append(dict(**pair,max_channel_delta=maximum,differing_pixels=int(np.any(delta>0,axis=2).sum()),passed=okay))
        if not okay:value.setdefault('failures',[]).append('GPU comparison '+pair['case'])
    if gpu:save(out/'GPU_COMPARISONS.json',gpu)
    prior_runs=[f for f in work.glob('*/result.json') if f.parent!=out]
    result=dict(build_id=build_id,run_id=run_id,mode=mode,command=command,pid=process.pid,popen_monotonic_ns=before,exit_code=process.returncode,timed_out=timeout,seconds=time.monotonic()-start,diagnostics=diagnostics,engine=value,memory=memory_summary(samples),first_process_run=not prior_runs,prior_run_count=len(prior_runs),first_formal_track_run=(run_id=='target_60_1'),each_run_starts_new_process=True,os_disk_cache_cold_claim=False,external_presentation_timestamp=None,artifacts={p.name:sha(p) for p in target.parent.iterdir() if p.suffix in {'.exe','.pck'}},measurement_source=dict(frame='Godot monotonic main-loop intervals; every interval retained',gpu='Windows WDDM GPUProcessMemory DedicatedUsage, summed per process across adapter instances',private='GetProcessMemoryInfo PrivateUsage; not working-set substitute'))
    if (out/'frames.csv').exists():
        with (out/'frames.csv').open(newline='',encoding='utf-8') as f:rows=list(csv.DictReader(f))
        steady=[r for r in rows if r['phase']=='steady']
        result['frame_stats']=frame_summary([float(r['interval_ms']) for r in steady])
        result['all_phase_frame_stats']=frame_summary([float(r['interval_ms']) for r in rows])
        result['steady_duration_observed_sec']=max(float(r['track_seconds']) for r in steady)-min(float(r['track_seconds']) for r in steady)
        result['long_frames']=[r for r in rows if float(r['interval_ms'])>33]
        result['accounting']=dict(resident_peak=max(int(r['resident_bytes']) for r in rows),reserved_peak=max(int(r['reserved_bytes']) for r in rows),total_peak=max(int(r['resident_bytes'])+int(r['reserved_bytes']) for r in rows),inflight_peak=max(int(r['inflight']) for r in rows),engine_texture_peak=max(float(r['engine_texture_bytes']) for r in rows),engine_buffer_peak=max(float(r['engine_buffer_bytes']) for r in rows))
        page_ready={}
        with (out/'resource_events.jsonl').open(encoding='utf-8') as events:
            for line in events:
                event=json.loads(line)
                if event.get('event')=='page_state' and event.get('state')=='RESIDENT' and event.get('key','').startswith('fine_'):
                    page_ready.setdefault(event['key'],event['usec'])
        result['startup_phase_clarification']=dict(first_city_details_ready_usec=value.get('first_details_ready_usec'),first_all_12_initial_fine_pages_ready_usec=max(page_ready.values()) if len(page_ready)==12 else None,initial_fine_page_first_ready=page_ready,first_gpu_presented_usec=None,note='engine lifecycle timestamps; no external GPU presentation time is inferred')
        ready=next(e for e in value['startup'] if e['event']=='app_ready')['usec'];last_end=int(rows[-1]['process_start_usec'])+float(rows[-1]['interval_ms'])*1000
        result['steady_clock_window_sec']=(last_end-ready-value['warmup_sec']*1000000)/1000000
    if (out/'ab_frames.csv').exists():
        with (out/'ab_frames.csv').open(newline='',encoding='utf-8') as f:ab=list(csv.DictReader(f))
        result['frame_stats']=frame_summary([float(r['interval_ms']) for r in ab if r['phase']=='steady']);result['long_frames']=[r for r in ab if float(r['interval_ms'])>33]
        result['logical_byte_column_scope']='new bridge: actual E3 resident estimate; legacy CSV zeros are uninstrumented placeholders, not measured zero memory. WDDM and private measurements remain available for both.'
    result['execution_passed']=process.returncode==0 and not timeout and not diagnostics and not value.get('failures')
    result['budget_passed']=(result.get('frame_stats',{}).get('budget_passed') and result['memory']['private_budget_passed'] and result['memory']['gpu_budget_passed']) if mode=='performance' else None
    result['gpu_counter_missing_samples']=sum(r.get('gpu_dedicated_bytes') is None for r in samples)
    save(out/'result.json',result)
    print('Q1_RUN',run_id,'execution',result['execution_passed'],'budget',result['budget_passed'],'frames',result.get('frame_stats'),'memory',result['memory'],'failures',value.get('failures'), 'diagnostics',diagnostics[:4],flush=True)
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);p.add_argument('--run-id',required=True);p.add_argument('--mode',default='performance');p.add_argument('--seconds',type=float,default=60);p.add_argument('--warmup',type=float,default=10);p.add_argument('--extra',action='append',default=[]);a=p.parse_args()
    if not all(re.fullmatch('[A-Za-z0-9_-]+',v) for v in [a.build_id,a.run_id,a.mode]):raise ValueError('unsafe id')
    r=run(a.build_id,a.run_id,a.mode,a.seconds,a.warmup,a.extra);return 0 if r['execution_passed'] else 1
if __name__=='__main__':raise SystemExit(main())
