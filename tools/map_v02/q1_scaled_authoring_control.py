"""RCA control: preserve the same logical lock ROI through viewport stretching."""
import os,shutil,subprocess,re
from common import ROOT,read,save,sha
from v1_build import GODOT

def main():
    work=ROOT/'review-work/map_v02/q1_regression_native_e2e';stage=work/'authoring';out=ROOT/'review-work/map_v02/q1_scaled_authoring_control';out.mkdir(exist_ok=False)
    shutil.copyfile(ROOT/'tools/map_v02/q1_authoring_pixel_probe.gd',stage/'q1_authoring_pixel_probe.gd')
    launcher=stage/'q1_authoring_probe_runner.gd';launcher.write_text('extends SceneTree\nfunc _initialize() -> void:call_deferred("run")\nfunc run() -> void:\n\tvar boot=Node.new();root.add_child(boot)\n\tawait load("res://q1_authoring_pixel_probe.gd").new().run(boot)\n',encoding='utf-8')
    env=os.environ.copy();env['APPDATA']=str(out/'isolated_user_data')
    command=[GODOT,'--fullscreen','--path',str(stage),'--script','res://q1_authoring_probe_runner.gd','--','--report='+str(out/'result.json')]
    process=subprocess.run(command,capture_output=True,timeout=150,env=env);text=(process.stdout+process.stderr).decode('utf-8',errors='replace');(out/'runtime.txt').write_text(text,encoding='utf-8');diagnostics=re.findall(r'^.*(?:SCRIPT ERROR:|ERROR:|WARNING:|ObjectDB.*leaked|Resource.*still in use).*$',text,re.M)
    value=read(out/'result.json') if (out/'result.json').exists() else dict(failures=['missing result'])
    rows=[read(p) for p in sorted(out.glob('protected_*.json'))]
    save(out/'RCA.json',dict(passed=process.returncode==0 and not diagnostics and not value.get('failures'),command=command,exit_code=process.returncode,diagnostics=diagnostics,samples=rows,old_incorrect_crop_unique_hashes=len({r['old_incorrect_crop_hash'] for r in rows}),corrected_png_unique_hashes=len({sha(p) for p in out.glob('protected_*.png')}),logical_region_unchanged=[70,65],threshold='exact pixel equality; unchanged',old_source_files_changed=False,api_reference='https://docs.godotengine.org/en/4.6/classes/class_viewport.html#class-viewport-method-get-stretch-transform'))
    print('Q1_SCALED_AUTHORING_CONTROL',process.returncode,'failures',value.get('failures'),'diagnostics',diagnostics[:4]);return process.returncode
if __name__=='__main__':raise SystemExit(main())
