"""Bounded engineering metadata and existing-art fixtures, never historical content."""
from common import RUNTIME,read
from e1_compile import Writer,finish,sprite,digest,canonical_fixed6
from e3_build import terrain
import hashlib

def compile_sites(target,build_id,count=32):
    writer=Writer(target);old=read(RUNTIME/'v02/v1/style.json')['assets']['gate'];source=RUNTIME/old['path'][6:]
    texture=writer.texture('assets/gate.png',source.read_bytes())
    from PIL import Image
    asset=dict(asset_id='gate',style_id='engineering_existing_asset',texture_file=texture['path'],rect_px=[0,0,*Image.open(source).size],anchor_px=old['anchor_px'],width_m=old['width_m'],ground_footprint_m=[[-10,-5],[10,-5],[10,5],[-10,5]],protection_envelope_m=[-165,-30,330,60],allowed_directions=['source_fixed'],damage_variants=[])
    writer.data('assets/art_bundle.json',dict(schema_version=1,assets=[asset]))
    b=[0,0,8192,4096];row=writer.texture('terrain/root.png',terrain(b))
    pages=[dict(id='root',level=0,x=0,y=0,bounds_m=b,parent_id='',texture_files=[row['path']],texture_sha256=row['sha256'],core_px=[256,256],gutter_px=4,allowed_mip_levels=[0],optional=False)]
    coords=dict(axis='east_south',unit='meter',origin_m=[0,0]);compat=dict(world_id='stream_lab_v02',site_id='q1.engineering_sites',layout_version='q1_sites_32_v1',layout_slots_sha256=digest([]),fixed_refs_sha256=digest('engineering_only'),graph_version='lab_visual_no_corridors',coordinate_sha256=hashlib.sha256(canonical_fixed6(coords).encode()).hexdigest())
    sites=[];objects=[]
    for i in range(count):
        p=[256+(i%32)*220,256+(i//32)*64] if count>32 else [256+(i%8)*700,256+(i//8)*700]
        sites.append(dict(site_id='lab.site.%04d'%i,position_m=p,label='工程地点 %04d'%i,importance=i%7,slots=[],logical_authority=False))
        if count==32 and i in [9,10,17,18]:
            item=sprite('lab.detail.%04d.gate'%i,p,'gate',asset);item['site_id']=sites[-1]['site_id'];objects.append(item)
    return finish(writer,build_id,compat,coords,pages,objects,sites,dict(kind='engineering_sites_or_labels',historical_content=False,site_count=count,detail_sites=4 if count==32 else 0,asset_source='existing V1 gate; no new art',proxy_markers='selection anchors; not duplicated gate geometry'),b)
