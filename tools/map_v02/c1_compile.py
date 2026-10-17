"""C1 packages reuse sealed R1 pixels and V2 assets; nothing writes old inputs."""
import io,copy
from PIL import Image
from common import ROOT,RUNTIME,read,sha
from e1_compile import Writer,finish,sprite,polyline,validate_package,canonical_fixed6
import hashlib
from e3_build import compile_stream

def encoded(image):
    out=io.BytesIO();image.save(out,format='PNG');return out.getvalue()

def combined(ground,water):
    return Image.alpha_composite(Image.open(ground).convert('RGBA'),Image.open(water).convert('RGBA'))

def compile_real(snapshot_path,target,build_id):
    snapshot=read(snapshot_path);writer=Writer(target);assets={};textures={}
    style=read(RUNTIME/'v02/v1/style.json');v2=read(RUNTIME/'v02/v2/assets.json')
    for key,old in {**{k:style['assets'][k] for k in ['tree_willow','tree_grove','gate']},**v2['assets']}.items():
        source=RUNTIME/old['path'][6:]
        if sha(source)!=old['sha256']:raise ValueError('asset drift '+key)
        if source not in textures:textures[source]=writer.texture('assets/'+source.name,source.read_bytes())
        size=list(Image.open(source).size);width=old.get('width_m',size[0]*old.get('pixel_scale_m',1))
        assets[key]=dict(asset_id=key,style_id=style['style_id'],texture_file=textures[source]['path'],rect_px=old.get('rect_px',[0,0,*size]),anchor_px=old['anchor_px'],width_m=width,
            ground_footprint_m=old.get('ground_polygon_m',[[-10,-5],[10,-5],[10,5],[-10,5]]),protection_envelope_m=[-170,-160,340,320],allowed_directions=['source_fixed'],damage_variants=[],source_sha256=old['sha256'])
    writer.data('assets/art_bundle.json',dict(schema_version=1,assets=list(assets.values())))
    objects=[]
    for row in snapshot['objects']:
        objects.append(sprite(row['id'],row['position_m'],'tree_willow' if row['asset_version']==1 else 'tree_grove',assets['tree_willow' if row['asset_version']==1 else 'tree_grove'],row))
    for i,p in enumerate(style['sample_trees_m']):
        key='tree_willow' if i%3==0 else 'tree_grove'
        objects.append(sprite('v1.preview.Tree_%02d'%i,p,key,assets[key],dict(role='accepted_v1_review_placement_only')))
    objects.append(sprite('tongguan.gate.main',[0,0],'gate',assets['gate']))
    objects.append(sprite('tongguan.wall.north',[-106.49609375,-156.0640625],'wall_ns',assets['wall_ns']))
    refs=snapshot['authoring']['fixed_refs'];objects.extend([polyline('presentation.main_corridor.base',refs['main_corridor'],'988c6d73',12),polyline('presentation.main_corridor',refs['main_corridor'],'d2bb8c',8),polyline('presentation.main_corridor.light',refs['main_corridor'],'e0ce9e99',4)])
    for road in snapshot['authoring']['roads']:
        objects.extend([polyline(road['id']+'.base',road['points_m'],'a99b77',7),polyline(road['id'],road['points_m'],'d6c395',4.6)])
    for slot in snapshot['slots']:
        if slot['id'] not in ['tongguan.slot.rear_storage_01','tongguan.slot.rear_military_01']:continue
        p=[sum(v[i] for v in slot['polygon_local_m'])/len(slot['polygon_local_m']) for i in range(2)]
        objects.append(polyline('presentation.socket.'+slot['id'],[slot['road_socket_m'],[p[0]+142*80/1536,p[1]+140*80/1536]],'d2bb8c',3))
    config=read(RUNTIME/'v02/relief_r01/terrain.json');base=RUNTIME/'v02/relief_r01/assets'
    # Composite only the existing layers, so all streamed pages are opaque.
    context=combined(base/'context_ground.png',base/'context_water.png')
    root=writer.texture('terrain/context.png',encoded(context))
    pages=[dict(id='context',level=0,x=0,y=0,bounds_m=config['context']['bounds_m'],parent_id='',texture_files=[root['path']],texture_sha256=root['sha256'],core_px=list(context.size),gutter_px=0,allowed_mip_levels=[0],optional=False)]
    for y in range(3):
        for x in range(4):
            row=writer.texture(f'terrain/fine_{x}_{y}.png',encoded(combined(base/f'ground_{x}_{y}.png',base/f'water_{x}_{y}.png')))
            pages.append(dict(id=f'fine_{x}_{y}',level=1,x=x-2,y=y-2,bounds_m=[-1024+x*512,-1024+y*512,512,512],parent_id='context',texture_files=[row['path']],texture_sha256=row['sha256'],core_px=[1024,1024],gutter_px=32,allowed_mip_levels=[0],optional=False))
    writer.data('receipts/effective_snapshot.json',snapshot)
    writer.data('receipts/terrain_review.json',dict(status='candidate_pending_user_review',source_build='tongguan_v02_relief_r01_20261016_02',feedback='好很多',scope='positive terrain feedback; integration still pending',terrain_sha256=sha(RUNTIME/'v02/relief_r01/terrain.json'),new_art_count=0))
    sites=[dict(site_id='tongguan',position_m=[0,0],label='潼关',slots=snapshot['slots'],importance=100,logical_authority=False)]
    provenance=dict(kind='c1_r1_v2_integration',source_snapshot_sha256=sha(snapshot_path),raw_instance_ids=snapshot['raw_instance_ids'],source_inputs=snapshot['source_inputs'],source_effective_ids=[r['id'] for r in snapshot['objects']],deleted_ids=snapshot['authoring']['deleted_ids'],pins=snapshot['authoring']['pinned_tree_ids'],slot_pins=snapshot['authoring']['slot_pins'],generator_version=snapshot['generator_version'],source_format_versions=snapshot['source_format_versions'],terrain_manifest_sha256=sha(RUNTIME/'v02/relief_r01/terrain.json'),visual_review='pending',candidate_art_receipt='receipts/terrain_review.json',baked_representation='immutable R1 ground and water only',dynamic_representation='all trees, buildings, wall damage, army, labels, faction',style_migration_scope=dict(source_map_written=False,candidate_only=True))
    provenance['effective_authoring_sha256']=hashlib.sha256(canonical_fixed6(snapshot['authoring']).encode()).hexdigest()
    return finish(writer,build_id,snapshot['compatibility'],snapshot['coordinates'],pages,objects,sites,provenance,config['context']['bounds_m'])

def compile_multi(target,build_id):
    manifest=compile_stream(target,build_id)
    # The engineering package remains under the identical E1 protocol / E3 loader.
    from common import save
    sites=[dict(site_id='lab.site.%03d'%i,position_m=[256+(i%32)*512,256+(i//32)*512],label='工程地点 %03d'%i,slots=[],importance=i%7,logical_authority=False) for i in range(256)]
    save(target/'settlements/sites.json',dict(schema_version=1,sites=sites,authority='presentation_only'))
    for row in manifest['files']:
        if row['path']=='settlements/sites.json':row['sha256']=sha(target/row['path'])
    save(target/'presentation.package.json',manifest);validate_package(target,manifest['compatibility'])
    return manifest
