"""Serial formal measurements only; every required run completes even if a budget fails."""
import argparse,json,subprocess
import win32com.client
from common import ROOT,read,save,sha
from q1_run import run

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--build-id',required=True);a=parser.parse_args();work=ROOT/'review-work/map_v02'/a.build_id
    wmi=win32com.client.GetObject(r'winmgmts:\\.\root\cimv2')
    hardware={}
    for name,query,fields in [('cpu','Win32_Processor',['Name','NumberOfCores','NumberOfLogicalProcessors']),('system','Win32_ComputerSystem',['TotalPhysicalMemory']),('gpu','Win32_VideoController',['Name','DriverVersion','AdapterRAM'])]:
        hardware[name]=[{field:getattr(row,field) for field in fields} for row in wmi.ExecQuery('SELECT '+','.join(fields)+' FROM '+query)]
    inventory=[dict(pid=int(r.ProcessId),name=str(r.Name)) for r in wmi.ExecQuery('SELECT ProcessId,Name FROM Win32_Process') if 'godot' in str(r.Name).lower() or 'tongguan' in str(r.Name).lower()]
    hardware['godot_processes_before_formal_measurement']=inventory
    if inventory:raise RuntimeError('finish owned native checks before formal GPU measurement; no unrelated processes are terminated')
    for key,cmd in [('nvidia',['nvidia-smi','--query-gpu=name,driver_version,memory.total,memory.used,utilization.gpu','--format=csv,noheader,nounits']),('power_scheme',['powercfg','/getactivescheme'])]:
        p=subprocess.run(cmd,capture_output=True,timeout=20);hardware[key]=dict(command=cmd,output=p.stdout.decode('utf-8',errors='replace'),exit_code=p.returncode)
    save(work/'FORMAL_ENVIRONMENT.json',hardware);save(work/'FROZEN_MEASUREMENT.json',dict(artifacts=read(work/'ARTIFACTS.json'),source_manifest_sha256=sha(work/'SOURCE_MANIFEST.json'),profile_sha256=sha(ROOT/'schemas/map_v02/q1_profiles.json'),q1_run_sha256=sha(ROOT/'tools/map_v02/q1_run.py'),cold_disk_cache_claim=False))
    results=[]
    for name,seconds in [('target_60_1',60),('target_60_2',60),('target_60_3',60),('target_300',300)]:
        r=run(a.build_id,name,seconds=seconds,warmup=10);results.append(r)
        save(work/'FORMAL_PROGRESS.json',dict(completed=[x['run_id'] for x in results],execution_all=all(x['execution_passed'] for x in results),budgets_all=all(x['budget_passed'] for x in results)))
    for mode in ['old','new']:
        r=run(a.build_id,'ab_60_'+mode,'ab',seconds=60,warmup=3,extra=['--ab-mode='+mode]);results.append(r)
    save(work/'BENCHMARK_SUMMARY.json',dict(runs=[dict(run_id=r['run_id'],execution_passed=r['execution_passed'],budget_passed=r['budget_passed'],frame_stats=r.get('frame_stats'),memory=r['memory']) for r in results],normal_execution_passed=all(r['execution_passed'] for r in results[:4]),normal_budgets_passed=all(r['budget_passed'] for r in results[:4]),ab_execution_passed=all(r['execution_passed'] for r in results[4:]),worst_normal_p95_ms=max(r['frame_stats']['p95_ms'] for r in results[:4]),worst_normal_p99_ms=max(r['frame_stats']['p99_ms'] for r in results[:4])))
    return 0 if all(r['execution_passed'] for r in results) else 1
if __name__=='__main__':raise SystemExit(main())
