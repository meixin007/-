"""Run the exported E3 package and sample owned-process private bytes."""
import argparse,ctypes,re,subprocess,time
from ctypes import wintypes
from common import ROOT,read,save,sha

class MemoryCounters(ctypes.Structure):
    _fields_=[('cb',wintypes.DWORD),('PageFaultCount',wintypes.DWORD),*[(name,ctypes.c_size_t) for name in ['PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage','PrivateUsage']]]

def memory(pid):
    kernel=ctypes.windll.kernel32;psapi=ctypes.windll.psapi
    kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];kernel.OpenProcess.restype=wintypes.HANDLE
    kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    psapi.GetProcessMemoryInfo.argtypes=[wintypes.HANDLE,ctypes.POINTER(MemoryCounters),wintypes.DWORD]
    handle=kernel.OpenProcess(0x410,False,pid)
    if not handle:return None
    try:
        counters=MemoryCounters();counters.cb=ctypes.sizeof(counters)
        return dict(private_bytes=counters.PrivateUsage,working_set=counters.WorkingSetSize) if psapi.GetProcessMemoryInfo(handle,ctypes.byref(counters),counters.cb) else None
    finally:kernel.CloseHandle(handle)

def main():
    p=argparse.ArgumentParser();p.add_argument('--build-id',required=True);p.add_argument('--run-id',required=True);a=p.parse_args()
    if not all(re.fullmatch('[A-Za-z0-9_-]+',s) for s in [a.build_id,a.run_id]):raise ValueError('id')
    work=ROOT/'review-work/map_v02'/a.build_id;clean=work/'CLEAN_WINDOWS';out=work/a.run_id;out.mkdir(exist_ok=False)
    if (clean/'.godot').exists() or (clean/'project.godot').exists():raise RuntimeError('not clean')
    command=[str(clean/'TongguanE3.exe'),'--fullscreen','--log-file',str(out/'runtime.log'),'--','--e3-check','--report='+str(out/'result.json')]
    start=time.monotonic();samples=[];process=subprocess.Popen(command,cwd=clean,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    timed_out=False
    while True:
        value=memory(process.pid)
        if value:samples.append(dict(seconds=time.monotonic()-start,**value))
        try:stdout,stderr=process.communicate(timeout=.5);break
        except subprocess.TimeoutExpired:
            if time.monotonic()-start>335:
                process.kill();stdout,stderr=process.communicate();timed_out=True;break
    raw=stdout+stderr;(out/'console.txt').write_bytes(raw)
    text=(out/'runtime.log').read_text(encoding='utf-8',errors='replace') if (out/'runtime.log').exists() else raw.decode('utf-8',errors='replace')
    (out/'runtime.txt').write_text(text,encoding='utf-8')
    diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
    result=read(out/'result.json') if (out/'result.json').exists() else dict(failures=['missing result'])
    passed=process.returncode==0 and not timed_out and not diagnostics and not result.get('failures')
    result.update(technical_passed=passed,command=command,cwd=str(clean),exit_code=process.returncode,diagnostics=diagnostics,timed_out=timed_out,seconds=time.monotonic()-start,process_memory_samples=samples,private_bytes_peak=max((s['private_bytes'] for s in samples),default=None),memory_sampling='owned process GetProcessMemoryInfo; allocator/RSS separate from resource references',artifacts={p.name:sha(p) for p in clean.iterdir() if p.suffix in {'.exe','.pck'}})
    save(out/'result.json',result)
    print('E3_NATIVE',passed,'checks',result.get('checks'),'failures',result.get('failures'),'diagnostics',diagnostics[:10],flush=True)
    return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
