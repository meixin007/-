"""E1 immutable presentation compiler; source maps, images and gameplay stay read-only."""
from pathlib import Path, PurePosixPath
import copy, hashlib, io, json, math, re, shutil
import numpy as np
from PIL import Image
from common import ROOT, RUNTIME, read, save, sha, git

VERSION = 'e1_compiler_v1'
IMPORT_CONTRACT = dict(engine_major=4,engine_minor=6,texture_compression='lossless',fix_alpha_border=False,premult_alpha=False,mipmaps=False,pixel_hash='rgba8_base_only')
COMPAT = ['world_id', 'site_id', 'layout_version', 'layout_slots_sha256', 'fixed_refs_sha256', 'graph_version', 'coordinate_sha256']


class PackageError(ValueError):
    def __init__(self, code, detail=''):
        self.code = code
        super().__init__(code + ': ' + detail)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def canonical_fixed6(value):
    if isinstance(value, dict):return '{'+','.join(json.dumps(str(k),ensure_ascii=False)+':'+canonical_fixed6(value[k]) for k in sorted(value))+'}'
    if isinstance(value, list):return '['+','.join(canonical_fixed6(v) for v in value)+']'
    if isinstance(value, (int,float)) and not isinstance(value,bool):return f'{float(value):.6f}'
    return json.dumps(value,ensure_ascii=False,separators=(',',':'))


def safe_path(value):
    return isinstance(value, str) and bool(re.fullmatch(r'[A-Za-z0-9_./-]+', value)) and not value.startswith('/') and all(p not in {'', '.', '..'} for p in value.split('/')) and (value.endswith('.json') or value.endswith('.png.bin'))


def rect_overlap(a, b):
    return a[0] < b[0]+b[2] and b[0] < a[0]+a[2] and a[1] < b[1]+b[3] and b[1] < a[1]+a[3]


def relocate(record, delta):
    item = copy.deepcopy(record)
    item['position_m'] = [item['position_m'][i]+delta[i] for i in range(2)]
    item['paint_bounds_m'][:2] = [item['paint_bounds_m'][i]+delta[i] for i in range(2)]
    item['owner'] = [math.floor(v/512) for v in item['position_m']]
    return item


class Writer:
    def __init__(self, target):
        self.root = Path(target)
        self.root.mkdir(parents=True, exist_ok=False)
        self.files = []

    def data(self, path, value):
        save(self.root/path, value)
        self.files.append(dict(path=path, kind='json', required=True, sha256=sha(self.root/path)))

    def texture(self, path, encoded, required=True, present=True):
        image = Image.open(io.BytesIO(encoded)).convert('RGBA')
        row = dict(path=path+'.bin', kind='texture', required=required,
                   sha256=hashlib.sha256(encoded).hexdigest(), resource_path=path,
                   pixel_sha256=hashlib.sha256(image.tobytes()).hexdigest(),
                   pixel_size=list(image.size), estimated_rgba8_bytes=image.width*image.height*4)
        if present:
            target = self.root/path;target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(encoded)
            (self.root/(path+'.bin')).write_bytes(encoded)
        self.files.append(row)
        return row


def sprite(id, position, asset_id, asset, source=None):
    width = asset['width_m']; scale = width/asset['rect_px'][2]
    anchor = asset['anchor_px']; rect = asset['rect_px']
    bounds = [position[0]-anchor[0]*scale, position[1]-anchor[1]*scale, rect[2]*scale, rect[3]*scale]
    return dict(id=id, source_key=id, record_type='sprite', position_m=position,
                owner=[math.floor(v/512) for v in position], asset_id=asset_id,
                paint_bounds_m=bounds, ground_footprint_m=asset['ground_footprint_m'],
                protection_envelope_m=asset['protection_envelope_m'],
                render_plane=2, ground_depth=position[1], source_record=copy.deepcopy(source or {}))


def polyline(id, points, color, width, plane=1):
    xs,ys=zip(*points);position=list(points[0])
    return dict(id=id, source_key=id, record_type='polyline', position_m=position,
                owner=[math.floor(v/512) for v in position], points_m=points,
                color=color, width_m=width, paint_bounds_m=[min(xs)-width,min(ys)-width,max(xs)-min(xs)+2*width,max(ys)-min(ys)+2*width],
                render_plane=plane, ground_depth=position[1])


def shared_assets(writer):
    style = read(RUNTIME/'v02/v1/style.json')
    textures = {}
    assets = []
    for key in ['tree_willow','tree_grove','gate']:
        old = style['assets'][key]
        source = RUNTIME/old['path'][6:]
        if sha(source) != old['sha256']:
            raise PackageError('source_asset_drift',key)
        if str(source) not in textures:
            textures[str(source)]=writer.texture('assets/'+source.name,source.read_bytes())
        texture=textures[str(source)]
        image=Image.open(source)
        assets.append(dict(asset_id=key,style_id=style['style_id'],texture_file=texture['path'],
            rect_px=old.get('rect_px',[0,0,*image.size]),anchor_px=old['anchor_px'],width_m=old['width_m'],
            ground_footprint_m=[[-10,-5],[10,-5],[10,5],[-10,5]],
            protection_envelope_m=[-50,-50,100,100] if key.startswith('tree') else [-165,-30,330,60],
            allowed_directions=['source_fixed'],damage_variants=[],source_sha256=old['sha256']))
    writer.data('assets/art_bundle.json',dict(schema_version=1,assets=assets))
    return {r['asset_id']:r for r in assets}


def finish(writer, build_id, compatibility, coordinates, pages, objects, sites, provenance, bounds):
    ids=set()
    for item in objects:
        if item['id'] in ids:raise PackageError('duplicate_object_id',item['id'])
        if item.get('source_key',item['id'])!=item['id']:raise PackageError('source_key_mismatch',item['id'])
        ids.add(item['id'])
    for page in pages:
        page.update(build_id=build_id,object_ids=[o['id'] for o in objects if rect_overlap(o['paint_bounds_m'],page['bounds_m'])],object_shards=['instances/objects.json'])
    writer.data('instances/objects.json',dict(schema_version=1,objects=objects))
    writer.data('settlements/sites.json',dict(schema_version=1,sites=sites,authority='presentation_only'))
    writer.data('receipts/provenance.json',provenance)
    writer.data('world.catalog.json',dict(schema_version=1,build_id=build_id,compatibility=compatibility,coordinates=coordinates,
        bounds_m=bounds,pages=pages,art_bundle='assets/art_bundle.json',object_shards=['instances/objects.json'],sites='settlements/sites.json',provenance='receipts/provenance.json'))
    receipt=ROOT/'reports/map_v02/V1_A01_ACCEPTED_20261016.json'
    writer.data('receipts/visual_review.json',read(receipt))
    manifest=dict(schema_id='tongguan.presentation_package',schema_version=1,build_id=build_id,
        compiler_version=VERSION,source_commit=git('rev-parse','HEAD'),compatibility=compatibility,
        style_id=read(receipt)['style_id'],visual_review_sha256=sha(receipt),catalog='world.catalog.json',
        files=writer.files,load_policy='synchronous_e1_no_residency_budget',import_contract=IMPORT_CONTRACT.copy())
    save(writer.root/'presentation.package.json',manifest)
    validate_package(writer.root,compatibility)
    return manifest


def lab_texture(bounds, core=256, gutter=4):
    coords=(np.arange(core+gutter*2)-gutter+.5)*bounds[2]/core
    x,y=np.meshgrid(bounds[0]+coords,bounds[1]+coords)
    bank=-470+38*np.sin(x/260)+14*np.sin(x/93)
    shade=np.sin(x/410)*np.cos(y/355)
    rgb=np.empty((core+gutter*2,core+gutter*2,3),dtype=np.uint8)
    water=y<bank
    for i,(land,wet) in enumerate([(197,145),(195,183),(160,182)]):
        rgb[:,:,i]=np.clip(np.where(water,wet,land)+shade*5+np.sin((x+y)/83)*1.7,0,255)
    out=io.BytesIO();Image.fromarray(rgb).save(out,format='PNG');return out.getvalue()


def compile_lab(target,build_id):
    writer=Writer(target);assets=shared_assets(writer)
    coordinates=dict(axis='east_south',unit='meter',origin_m=[0,0])
    compatibility=dict(world_id='stream_lab_v02',site_id='lab.site.proxy',layout_version='lab_4x4_v1',
        layout_slots_sha256=digest([]),fixed_refs_sha256=digest('lab_visual_only'),graph_version='lab_visual_no_corridors',coordinate_sha256=hashlib.sha256(canonical_fixed6(coordinates).encode()).hexdigest())
    objects=[sprite('lab.tree.cross_border',[-5,-5],'tree_grove',assets['tree_grove']),
             polyline('lab.road.boundary',[[-1000,120],[-200,160],[500,260],[1000,220]],'d2bb8c',12),
             polyline('lab.water.bank',[[x,-470+38*math.sin(x/260)+14*math.sin(x/93)] for x in range(-1024,1025,32)],'8e9477',3)]
    pages=[]
    for level,n,span,prefix in [(0,1,2048,'root'),(1,2,1024,'parent'),(2,4,512,'fine')]:
        for row in range(n):
            for col in range(n):
                bounds=[-1024+col*span,-1024+row*span,span,span]
                missing=level==2 and col==2 and row==1
                texture=writer.texture(f'terrain/{prefix}_{col}_{row}.png',lab_texture(bounds),not missing,not missing)
                parent='' if level==0 else (f'root_0_0' if level==1 else f'parent_{col//2}_{row//2}')
                pages.append(dict(id=f'{prefix}_{col}_{row}',level=level,x=col-2 if level==2 else col,y=row-2 if level==2 else row,
                    bounds_m=bounds,parent_id=parent,texture_files=[texture['path']],texture_sha256=texture['sha256'],core_px=[256,256],gutter_px=4,allowed_mip_levels=[0],optional=missing))
    sites=[dict(site_id='lab.site.proxy',position_m=[260,300],label='工程地点 A',slots=[],logical_authority=False)]
    return finish(writer,build_id,compatibility,coordinates,pages,objects,sites,
        dict(kind='synthetic_4x4_fixture',generator_version='e1_continuous_lab_v1',historical_content=False),[-1024,-1024,2048,2048])


def compile_snapshot(snapshot_path,target,build_id):
    snapshot=read(snapshot_path)
    if snapshot.get('schema_id')!='tongguan.effective_map' or snapshot.get('schema_version')!=1:raise PackageError('unsupported_snapshot')
    raw=snapshot['raw_instance_ids']
    if len(set(raw))!=len(raw):raise PackageError('duplicate_raw_id')
    records=snapshot['objects']
    ids=[r['id'] for r in records]
    if len(set(ids))!=len(ids):raise PackageError('duplicate_object_id')
    if set(raw)!=set(ids):raise PackageError('raw_projection_mismatch')
    for item in records:
        if item['source_key']!=item['id']:raise PackageError('source_key_mismatch')
    writer=Writer(target);assets=shared_assets(writer)
    objects=[sprite(item['id'],item['position_m'],'tree_willow' if item['asset_version']==1 else 'tree_grove',assets['tree_willow' if item['asset_version']==1 else 'tree_grove'],item) for item in records]
    objects.append(sprite('tongguan.gate.main',[0,0],'gate',assets['gate']))
    objects.append(polyline('presentation.main_corridor',snapshot['authoring']['fixed_refs']['main_corridor'],'d2bb8c',9))
    for road in snapshot['authoring']['roads']:objects.append(polyline(road['id'],road['points_m'],'d2bb8c',6))
    fallback=writer.texture('terrain/overview.png',(RUNTIME/'bundle/terrain_fallback.png').read_bytes())
    pages=[dict(id='overview',level=0,x=0,y=0,bounds_m=[-12000,-8000,24000,16000],parent_id='',texture_files=[fallback['path']],texture_sha256=fallback['sha256'],core_px=fallback['pixel_size'],gutter_px=0,allowed_mip_levels=[0],optional=False)]
    terrain=read(RUNTIME/'v02/v1/terrain.json')
    tiles={}
    for tile in terrain['tiles']:
        source=RUNTIME/tile['path'][6:]
        if sha(source)!=tile['sha256']:raise PackageError('source_terrain_drift')
        row=writer.texture('terrain/'+source.name,source.read_bytes())
        key=(tile['left_m'],tile['top_m']);tiles.setdefault(key,[]).append((tile,row))
    for (x,y),rows in sorted(tiles.items()):
        pages.append(dict(id=f'detail_{int((x+1024)/512)}_{int((y+1024)/512)}',level=1,x=math.floor(x/512),y=math.floor(y/512),bounds_m=[x,y,512,512],parent_id='overview',texture_files=[r['path'] for t,r in rows],texture_sha256=rows[0][1]['sha256'],core_px=[1024,1024],gutter_px=4,allowed_mip_levels=[0],optional=False))
    writer.data('receipts/effective_snapshot.json',snapshot)
    sites=[dict(site_id='tongguan',position_m=[0,0],label='潼关',slots=snapshot['slots'],logical_authority=False)]
    provenance=dict(kind='validated_existing_publication',source_snapshot_sha256=sha(snapshot_path),source_inputs=snapshot['source_inputs'],
        publication_content_sha256=snapshot['publication_content_sha256'],effective_patch_sha256=snapshot['effective_patch_sha256'],source_v4_sha256=snapshot['source_v4_sha256'],
        generator_version=snapshot['generator_version'],source_format_versions=snapshot['source_format_versions'],raw_instance_ids=raw,
        source_effective_ids=ids,deleted_ids=snapshot['authoring']['deleted_ids'],pins=snapshot['authoring']['pinned_tree_ids'],slot_pins=snapshot['authoring']['slot_pins'],
        style_migration_scope=dict(approved_v1_build='tongguan_v02_v1_20261015_04',detail_bounds_m=terrain['bounds_local_m'],source_map_written=False))
    return finish(writer,build_id,snapshot['compatibility'],snapshot['coordinates'],pages,objects,sites,provenance,[-12000,-8000,24000,16000])


def validate_package(root,expected):
    root=Path(root);manifest=read(root/'presentation.package.json')
    if manifest.get('schema_id')!='tongguan.presentation_package' or manifest.get('schema_version')!=1:raise PackageError('unsupported_schema')
    for key in COMPAT:
        if manifest.get('compatibility',{}).get(key)!=expected.get(key) or key not in expected:raise PackageError('incompatible_'+key)
    files={};missing=[]
    for row in manifest['files']:
        path=row.get('path')
        if not safe_path(path) or (row['kind']=='texture' and row.get('resource_path')!=path[:-4]):raise PackageError('unsafe_path',str(path))
        if path in files:raise PackageError('duplicate_file_path',path)
        files[path]=row
        actual=(root/path).resolve()
        if not actual.is_relative_to(root.resolve()):raise PackageError('unsafe_path',path)
        if not actual.is_file():
            if row['required']:raise PackageError('missing_file',path)
            missing.append(path);continue
        if sha(actual)!=row['sha256']:raise PackageError('hash_mismatch',path)
    catalog=read(root/manifest['catalog'])
    if catalog['build_id']!=manifest['build_id'] or catalog['compatibility']!=manifest['compatibility']:raise PackageError('catalog_identity')
    objects=[];seen=set()
    for path in catalog['object_shards']:
        if path not in files:raise PackageError('undeclared_dependency',path)
        for item in read(root/path)['objects']:
            if item['id'] in seen:raise PackageError('duplicate_object_id',item['id'])
            if item.get('source_key',item['id'])!=item['id']:raise PackageError('source_key_mismatch',item['id'])
            if item['owner']!=[math.floor(v/512) for v in item['position_m']]:raise PackageError('owner_mismatch',item['id'])
            seen.add(item['id']);objects.append(item)
    pages={}
    for page in catalog['pages']:
        if page['id'] in pages:raise PackageError('duplicate_page_id')
        if page['build_id']!=manifest['build_id']:raise PackageError('page_build_mismatch')
        if not page['texture_files'] or any(p not in files for p in page['texture_files']):raise PackageError('undeclared_dependency')
        if any(id not in seen for id in page['object_ids']):raise PackageError('unknown_object')
        pages[page['id']]=page
    for page in pages.values():
        if page['texture_sha256']!=files[page['texture_files'][0]]['sha256']:raise PackageError('page_texture_identity')
        parent=page['parent_id']
        if parent and (parent not in pages or pages[parent]['level']>=page['level']):raise PackageError('invalid_parent')
    return dict(passed=True,objects=len(objects),optional_missing=missing)
