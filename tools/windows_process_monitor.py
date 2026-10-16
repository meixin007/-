"""Run native release acceptance and measure the actual Windows process."""
from pathlib import Path
import argparse,ctypes as C,json,subprocess,time,re,statistics
ROOT=Path(__file__).resolve().parents[1]
class Memory(C.Structure):
    _fields_=[('cb',C.c_ulong),('PageFaultCount',C.c_ulong)]+[(k,C.c_size_t) for k in ['PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage','PrivateUsage']]
class PdhValue(C.Structure):
    _fields_=[('status',C.c_ulong),('padding',C.c_ulong),('value',C.c_longlong)]
class PdhItem(C.Structure):_fields_=[('name',C.c_wchar_p),('value',PdhValue)]
class Monitor:
    def __init__(self,pid):
        self.pid=pid;self.kernel=C.WinDLL('kernel32',use_last_error=True);self.psapi=C.WinDLL('psapi');self.kernel.OpenProcess.restype=C.c_void_p
        self.handle=self.kernel.OpenProcess(0x410,False,pid);self.pdh=C.WinDLL('pdh');self.query=C.c_void_p();self.counter=C.c_void_p();self.gpu_available=False
        if self.pdh.PdhOpenQueryW(None,0,C.byref(self.query))==0:
            self.gpu_available=self.pdh.PdhAddEnglishCounterW(self.query,C.c_wchar_p(r'\GPU Process Memory(*)\Dedicated Usage'),0,C.byref(self.counter))==0
    def memory(self):
        m=Memory();m.cb=C.sizeof(m)
        if not self.psapi.GetProcessMemoryInfo(C.c_void_p(self.handle),C.byref(m),C.sizeof(m)):return None
        return dict(working_set_bytes=int(m.WorkingSetSize),private_bytes=int(m.PrivateUsage))
    def gpu(self):
        if not self.gpu_available:return None
        if self.pdh.PdhCollectQueryData(self.query)!=0:return None
        size=C.c_ulong();count=C.c_ulong();self.pdh.PdhGetFormattedCounterArrayW(self.counter,0x400,C.byref(size),C.byref(count),None)
        if not size.value:return None
        buf=C.create_string_buffer(size.value)
        if self.pdh.PdhGetFormattedCounterArrayW(self.counter,0x400,C.byref(size),C.byref(count),buf)!=0:return None
        rows=C.cast(buf,C.POINTER(PdhItem));values=[int(rows[i].value.value) for i in range(count.value) if rows[i].name and rows[i].name.startswith(f'pid_{self.pid}_') and rows[i].value.status in [0,1]]
        return sum(values) if values else None
    def close(self):
        if self.handle:self.kernel.CloseHandle(C.c_void_p(self.handle))
        if self.query:self.pdh.PdhCloseQuery(self.query)