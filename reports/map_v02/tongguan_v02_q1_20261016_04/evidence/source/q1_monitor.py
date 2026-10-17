"""Windows owned-process sampling; measured WDDM GPU counters are never estimates."""
import ctypes,time
from ctypes import wintypes
import win32com.client
from e3_native import memory

class Observer:
    def __init__(self,pid):
        self.pid=pid;self.wmi=win32com.client.GetObject(r'winmgmts:\\.\root\cimv2');self.window=None
        self.user=ctypes.windll.user32
        self.user.GetWindowThreadProcessId.argtypes=[wintypes.HWND,ctypes.POINTER(wintypes.DWORD)]
        self.user.GetClientRect.argtypes=[wintypes.HWND,ctypes.POINTER(wintypes.RECT)]
        self.user.GetDpiForWindow.argtypes=[wintypes.HWND]
        self.user.IsWindowVisible.argtypes=[wintypes.HWND]
        self.user.SetThreadDpiAwarenessContext.argtypes=[wintypes.HANDLE];self.user.SetThreadDpiAwarenessContext.restype=wintypes.HANDLE
        self.user.SetThreadDpiAwarenessContext(wintypes.HANDLE(-4))
    def sample(self):
        row=dict(monotonic_ns=time.monotonic_ns(),**(memory(self.pid) or {}),gpu_dedicated_bytes=None,gpu_shared_bytes=None,gpu_committed_bytes=None,gpu_counter_status='unavailable')
        try:
            values=list(self.wmi.ExecQuery("SELECT Name,DedicatedUsage,SharedUsage,TotalCommitted FROM Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory WHERE Name LIKE 'pid_%d_%%'"%self.pid))
            if values:
                row.update(gpu_dedicated_bytes=sum(int(v.DedicatedUsage) for v in values),gpu_shared_bytes=sum(int(v.SharedUsage) for v in values),gpu_committed_bytes=sum(int(v.TotalCommitted) for v in values),gpu_counter_status='WDDM process memory counter',gpu_counter_instances=[str(v.Name) for v in values])
        except Exception as error:row['gpu_counter_error']=str(error)
        if self.window is None:
            handles=[]
            @ctypes.WINFUNCTYPE(wintypes.BOOL,wintypes.HWND,wintypes.LPARAM)
            def visit(handle,param):
                owner=wintypes.DWORD();self.user.GetWindowThreadProcessId(handle,ctypes.byref(owner))
                if owner.value==self.pid and self.user.IsWindowVisible(handle):handles.append(handle)
                return True
            self.user.EnumWindows(visit,0)
            if handles:self.window=handles[0]
        if self.window is not None:
            rect=wintypes.RECT()
            if self.user.GetClientRect(self.window,ctypes.byref(rect)):row['client_physical_size']=[rect.right-rect.left,rect.bottom-rect.top]
            row['window_dpi']=int(self.user.GetDpiForWindow(self.window))
        return row
