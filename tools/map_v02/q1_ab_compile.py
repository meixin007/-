"""Original v0.1 pixels and geometry for a matched compatibility-path A/B."""
from common import RUNTIME,read,save
from e1_compile import Writer,finish,sprite
from PIL import Image
import io

def compile_ab(target,build_id,snapshot):
    writer=Writer(target);assets={};original=read(RUNTIME/'bundle/art_descriptors.json');textures={}
    for key,d in original.items():
        source=RUNTIME/d['path'][6:]
        if source not in textures:textures[source]=writer.texture('assets/'+source.name,source.read_bytes())
        assets[key]=dict(asset_id=key,style_id='original_v01',texture_file=textures[source]['path'],rect_px=d['rect'],anchor_px=[d['anchor'][0]*d['rect'][2],d['anchor'][1]*d['rect'][3]],width_m=80,ground_footprint_m=[[-10,-5],[10,-5],[10,5],[-10,5]],protection_envelope_m=[-50,-50,100,100],allowed_directions=['source_fixed'],damage_variants=[])
    for name,file in [('ab_gate','bundle/art/gate_eastwest.png'),('ab_slope','bundle/slope.png')]:
        source=RUNTIME/file;r=writer.texture('assets/'+name+'.png',source.read_bytes());size=list(Image.open(source).size)
        assets[name]=dict(asset_id=name,style_id='original_v01',texture_file=r['path'],rect_px=[0,0,*size],anchor_px=[0,0],width_m=80,ground_footprint_m=[[-1,-1],[1,-1],[1,1],[-1,1]],protection_envelope_m=[-1,-1,2,2],allowed_directions=['source_fixed'],damage_variants=[])
    writer.data('assets/art_bundle.json',dict(schema_version=1,assets=list(assets.values())))
    objects=[sprite(r['id'],r['position_m'],'tree_willow' if r['asset_version']==1 else 'tree_grove',assets['tree_willow' if r['asset_version']==1 else 'tree_grove'],r) for r in snapshot['objects']]
    for name in ['ab_gate','ab_slope']:objects.append(sprite(name,[-99999,-99999],name,assets[name]))
    fallback=writer.texture('terrain/fallback.png',(RUNTIME/'bundle/terrain_fallback.png').read_bytes())
    pages=[dict(id='root',level=0,x=0,y=0,bounds_m=[-12000,-8000,24000,16000],parent_id='',texture_files=[fallback['path']],texture_sha256=fallback['sha256'],core_px=fallback['pixel_size'],gutter_px=0,allowed_mip_levels=[0],optional=False)]
    old_tiles=read(RUNTIME/'bundle/terrain_tiles.json')['tiles'];mapping={}
    for i,tile in enumerate(old_tiles):
        source=Image.open(RUNTIME/tile['path'][6:]).convert('RGBA');core=tile['core_px'];region=tile['source_region_px']
        # Preserve the original neighbor bleed, padding only outside the old field.
        import numpy as np
        a=np.array(source);left=max(0,8-int(region[0]));top=max(0,8-int(region[1]));right=max(0,core[2]+16-a.shape[1]-left);bottom=max(0,core[3]+16-a.shape[0]-top)
        padded=np.pad(a,((top,bottom),(left,right),(0,0)),mode='edge')[:core[3]+16,:core[2]+16]
        out=io.BytesIO();Image.fromarray(padded).save(out,format='PNG');r=writer.texture('terrain/old_%d.png'%i,out.getvalue());id='old_%d'%i
        pages.append(dict(id=id,level=1,x=i%3,y=i//3,bounds_m=[-12000+core[0]*40,-8000+core[1]*40,core[2]*40,core[3]*40],parent_id='root',texture_files=[r['path']],texture_sha256=r['sha256'],core_px=core[2:],gutter_px=8,allowed_mip_levels=[0],optional=False));mapping[tile['path']]=id
    sites=[dict(site_id='tongguan',position_m=[0,0],label='潼关',slots=snapshot['slots'],logical_authority=False)]
    m=finish(writer,build_id,snapshot['compatibility'],snapshot['coordinates'],pages,objects,sites,dict(kind='original_v01_AB_compatibility',source_effective_ids=[r['id'] for r in snapshot['objects']],source_effective_count=72,old_tile_mapping=mapping,original_descriptors=original,style='old pixels and unchanged original review canvas',scope='E2 query and E3 resource compatibility bridge; target C1 measured separately'),[-12000,-8000,24000,16000])
    return m
