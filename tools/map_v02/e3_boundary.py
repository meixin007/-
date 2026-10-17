"""Freeze pre-E3 files; never rewrites an existing boundary receipt."""
from common import ROOT,save,sha,source_files,scope_check,git

def main():
    folder=ROOT/'review-work/map_v02/e3_boundary'
    folder.mkdir(parents=True,exist_ok=False)
    files=[]
    for name in ['samples/tongguan_v01','docs/map_v02','reports/map_v02','schemas/map_v02','tools/map_v02','plugin-source']:
        files.extend(source_files(ROOT/name))
    files.extend([ROOT/'verify_repository.py',ROOT/'AGENTS.md'])
    save(folder/'before.json',dict(parent=git('rev-parse','HEAD'),scope=scope_check(),files=[dict(path=p.relative_to(ROOT).as_posix(),sha256=sha(p)) for p in sorted(set(files)) if p.name!='e3_boundary.py']))
    print('E3_BOUNDARY',len(files))

if __name__=='__main__':main()
