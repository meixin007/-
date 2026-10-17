"""Build one bounded V1 wash field from existing numerical terrain, not an illustration."""
from pathlib import Path
import hashlib, json, math, sys
import numpy as np
from PIL import Image, ImageDraw
from common import ROOT, RUNTIME, read, save, sha

DEST = RUNTIME / 'v02/v1'
BOUNDS = [-1024, -1024, 2048, 1536]
PALETTE = {'paper':'e4dcc2','land':'c5c3a0','ridge':'999c79','shadow':'8e9477','water':'91b7b6','deep_water':'7a9da1','shore':'bbb28e','road':'d2bb8c','ink':'555346','wall':'ddcdb0','roof':'788394','tree':'899274'}

def noise(x,y,scale,seed):
    x=x/scale; y=y/scale;ix=np.floor(x);iy=np.floor(y);fx=x-ix;fy=y-iy
    fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
    def h(a,b):
        value=np.sin(a*127.1+b*311.7+seed*17.3)*43758.5453
        return value-np.floor(value)
    a=h(ix,iy)*(1-fx)+h(ix+1,iy)*fx;b=h(ix,iy+1)*(1-fx)+h(ix+1,iy+1)*fx
    return a*(1-fy)+b*fy

def bilinear(field,x,y):
    x=(x+12000)/40-.5;y=(y+8000)/40-.5
    ix=np.floor(x).astype(int);iy=np.floor(y).astype(int);fx=x-ix;fy=y-iy
    ix=np.clip(ix,0,598);iy=np.clip(iy,0,398)
    return (field[iy,ix]*(1-fx)+field[iy,ix+1]*fx)*(1-fy)+(field[iy+1,ix]*(1-fx)+field[iy+1,ix+1]*fx)*fy

def main():
    output=DEST/'assets/terrain_v01'
    output.mkdir(parents=True,exist_ok=False)
    height=np.fromfile(RUNTIME/'bundle/elevation_f32.bin',dtype='<f4').reshape(400,600)
    gy,gx=np.gradient(height,40,40)
    water=read(RUNTIME/'bundle/modern_water.json')['features']
    records=[];core=1024;gutter=4;ppm=2.0
    # Rasterize source geometry once in global pixel space, then slice pages.
    # Per-page raster clipping can round negative vertices differently at seams.
    water_mask=Image.new('L',(4*core+2*gutter,3*core+2*gutter))
    water_draw=ImageDraw.Draw(water_mask)
    for feature in water:
        pts=[((p[0]-BOUNDS[0])*ppm+gutter,(p[1]-BOUNDS[1])*ppm+gutter) for p in feature['points_m']]
        if feature['geometry']=='polygon':water_draw.polygon(pts,fill=255)
        elif len(pts)>1:water_draw.line(pts,fill=255,width=5,joint='curve')
    for row in range(3):
        for col in range(4):
            left=-1024+col*512;top=-1024+row*512
            coords=(np.arange(core+2*gutter)-gutter+.5)/ppm
            x,y=np.meshgrid(left+coords,top+coords)
            dx=bilinear(gx,x,y);dy=bilinear(gy,x,y)
            shade=(.72+.48*dx+.58*dy)/np.sqrt(1+dx*dx+dy*dy)
            wash=noise(x,y,120,11)*.58+noise(x,y,38,23)*.28+noise(x,y,7,7)*.14
            grain=(noise(x,y,.8,19)-.5)*1.8
            # Global color mapping, no per-page auto contrast. Forty-meter DSM
            # governs the structure; fine marks express paint, not survey data.
            light=np.clip((shade-.69)*.8,-.22,.17)
            base=np.array([199.,197.,164.])[None,None,:]
            rgb=base+light[:,:,None]*np.array([82,85,71])[None,None,:]+(wash[:,:,None]-.5)*np.array([14,13,11])[None,None,:]+grain[:,:,None]
            ground=np.uint8(np.clip(rgb,0,255))
            mask=water_mask.crop((col*core,row*core,col*core+1032,row*core+1032))
            alpha=np.asarray(mask)
            wrgb=np.zeros((1032,1032,4),dtype=np.uint8)
            water_noise=noise(x,y,80,41)*.7+noise(x,y,12,53)*.3
            ripples=np.sin(x*.15+np.sin(y*.022)*2.0)*np.sin(y*.19+wash*1.2)
            for channel,value in enumerate([139,176,176]):wrgb[:,:,channel]=np.clip(value+(water_noise-.5)*9+ripples*1.4,0,255)
            wrgb[:,:,3]=alpha
            for kind,image in [('ground',Image.fromarray(ground)),('water',Image.fromarray(wrgb))]:
                path=output/f'{kind}_{col}_{row}.png';image.save(path)
                records.append({'kind':kind,'path':'res://v02/v1/assets/terrain_v01/'+path.name,'left_m':left,'top_m':top,'core_px':core,'gutter_px':gutter,'ppm':ppm,'sha256':sha(path)})
            print('V1_TERRAIN',col,row,flush=True)
    data={'stage':'V1','style_id':'tang_ink_wash_v02_candidate_a01','bounds_local_m':BOUNDS,'core_m':512,'core_px':1024,'gutter_px':4,'tiles':records,
          'numeric_source_sha256':sha(RUNTIME/'bundle/elevation_f32.bin'),'water_source_sha256':sha(RUNTIME/'bundle/modern_water.json'),'palette':PALETTE,'algorithm':'continuous_DSM_wash_v01_global_mask','world_sampling_seed':11,'historical_accuracy':'modern_reference_only','status':'candidate_pending_user_review'}
    save(DEST/'terrain.json',data)
    cameras={'composition':{'name':'关河组合','center_m':[0,-270],'zoom':.84},'gate':{'name':'关楼与接点','center_m':[20,-20],'zoom':2.1},'shore':{'name':'连续坡岸','center_m':[-60,-600],'zoom':1.4},'courtyard':{'name':'院落与接路','center_m':[-490,-220],'zoom':2.4}}
    assets={'gate':{'path':'res://bundle/art/gate_eastwest.png','anchor_px':[665,690],'width_m':330,'source':'existing selected gate, unchanged','sockets_px':{'north':[544,268],'south':[1097,956]}},
            'wall_ns':{'path':'res://v02/v1/assets/wall_ns_v01.png','anchor_px':[433,390],'pixel_scale_m':.14,'sockets_px':{'back':[433,390],'front':[1058,900]},'source':'built-in image_gen, new isolated candidate'},
            'warehouse':{'path':'res://v02/v1/assets/warehouse_v01.png','anchor_px':[788,660],'width_m':80,'ground_polygon_m':[[-21.77,-7.29],[-1.98,12.24],[21.98,-.52],[2.19,-12.5]],'source':'built-in image_gen, new isolated candidate'},
            'tree_willow':{'path':'res://bundle/art/trees.png','rect_px':[1024,0,512,512],'anchor_px':[256,399.36],'width_m':80,'source':'existing atlas region, unchanged'},
            'tree_grove':{'path':'res://bundle/art/trees.png','rect_px':[512,512,512,512],'anchor_px':[256,399.36],'width_m':80,'source':'existing atlas region, unchanged'}}
    for asset in assets.values():asset['sha256']=sha(RUNTIME/asset['path'][6:])
    assets['wall_ns'].update(south_mating_px=[490.142857,404.285714],south_insertion_m=[8,2],north_insertion_m=[7,6])
    trees=[[-850,-450],[-785,-470],[-710,-455],[-810,-385],[-730,-380],[-310,-430],[-240,-455],[-170,-410],[120,-365],[190,-340],[180,-265],[-850,450],[-780,440]]
    save(DEST/'style.json',{'style_id':data['style_id'],'candidate_number':1,'visual_review':'pending','reference_images':{'selected_gate':assets['gate']['path'],'tree_atlas':assets['tree_grove']['path'],'original_city_and_empty_terrain_images':'not_located; no exact-match claim'},'cameras':cameras,'assets':assets,'sample_trees_m':trees,'palette':PALETTE,'sun_direction_screen':[-.6,-.8],'ground_axes':{'map_east':[1,0],'map_south':[0,1],'sprite_foreshortening':'fixed in original raster assets; no camera rotation'},'line_weight_at_1x':'approximately 0.7-1.2 px at gate review camera','component_count':12,'new_painted_assets':2,'scope':'isolated presentation candidate; no saved-map, ID, layout, movement or registry changes'})
    make_scenes(records,assets,trees)

def make_scenes(records,assets,trees):
    terrain=['[gd_scene load_steps=25 format=3]','']
    for i,row in enumerate(records):terrain.append(f'[ext_resource type="Texture2D" path="{row["path"]}" id="{i+1}"]')
    terrain+=['','[node name="Terrain" type="Node2D"]','[node name="Ground" type="Node2D" parent="."]','[node name="Water" type="Node2D" parent="."]']
    for i,row in enumerate(records):
        parent='Ground' if row['kind']=='ground' else 'Water'
        terrain += [f'[node name="Tile_{i:02}" type="Sprite2D" parent="{parent}"]',f'position = Vector2({row["left_m"]}, {row["top_m"]})','scale = Vector2(0.5, 0.5)','centered = false','region_enabled = true','region_rect = Rect2(4, 4, 1024, 1024)','region_filter_clip_enabled = false',f'texture = ExtResource("{i+1}")']
    (DEST/'terrain.tscn').write_text('\n'.join(terrain)+'\n',encoding='utf-8')
    rig=['[gd_scene load_steps=9 format=3]','[ext_resource type="PackedScene" path="res://v02/v1/terrain.tscn" id="1"]','[ext_resource type="Script" path="res://v02/v1/rig.gd" id="2"]','[ext_resource type="Texture2D" path="res://bundle/art/gate_eastwest.png" id="3"]','[ext_resource type="Texture2D" path="res://v02/v1/assets/wall_ns_v01.png" id="4"]','[ext_resource type="Texture2D" path="res://v02/v1/assets/warehouse_v01.png" id="5"]','[ext_resource type="Texture2D" path="res://bundle/art/trees.png" id="6"]']
    for index,(name,rect) in enumerate([('Willow','Rect2(1024, 0, 512, 512)'),('Grove','Rect2(512, 512, 512, 512)')]):
        rig += [f'[sub_resource type="AtlasTexture" id="{name}"]','atlas = ExtResource("6")',f'region = {rect}','filter_clip = true']
    rig+=['[node name="CompositionRig" type="Node2D"]','script = ExtResource("2")','texture_filter = 4','[node name="Terrain" parent="." instance=ExtResource("1")]','[node name="Objects" type="Node2D" parent="."]','z_index = 2','y_sort_enabled = true']
    def sprite(name,texture,position,scale,anchor,z=0):
        rig.extend([f'[node name="{name}" type="Sprite2D" parent="Objects"]',f'position = Vector2({position[0]}, {position[1]})',f'scale = Vector2({scale}, {scale})','centered = false',f'offset = Vector2({-anchor[0]}, {-anchor[1]})',f'texture = {texture}',f'z_index = {z}'])
    gate_scale=330/1536
    ns=[(544-665)*gate_scale,(268-690)*gate_scale];ss=[(1097-665)*gate_scale,(956-690)*gate_scale]
    # No raster rotation/mirroring. Native oblique wall cuts meet source sockets.
    sprite('NorthWall','ExtResource("4")',[ns[0]-(1058-433)*.14+7,ns[1]-(900-390)*.14+6],.14,[433,390],-1)
    sprite('Gate','ExtResource("3")',[0,0],gate_scale,[665,690])
    sprite('SouthWall','ExtResource("4")',[ss[0]-8,ss[1]-2],.14,[433,390],1)
    sprite('Warehouse','ExtResource("5")',[-567.5,-227.5],80/1536,[788,660])
    for i,point in enumerate(trees):sprite(f'Tree_{i:02}','SubResource("Willow")' if i%3==0 else 'SubResource("Grove")',point,80/512,[256,399.36])
    (DEST/'composition.tscn').write_text('\n'.join(rig)+'\n',encoding='utf-8')

if __name__=='__main__':main()
