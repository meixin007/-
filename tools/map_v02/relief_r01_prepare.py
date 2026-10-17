"""Deterministic height-driven V2 relief candidate. Writes only its new namespace."""
import json,math
from pathlib import Path
import numpy as np
from scipy.ndimage import gaussian_filter
from PIL import Image,ImageDraw
from common import ROOT,RUNTIME,read,save,sha
from v1_prepare import noise

DEST=RUNTIME/'v02/relief_r01'
ORIGIN=[-12000,-8000]
BOUNDS=[-1024,-1024,2048,1536]
CORE=1024
GUTTER=32

def analyze(height,cell):
    h=np.asarray(height,dtype=np.float32)
    if h.ndim!=2 or not np.isfinite(h).all():raise ValueError('finite complete numeric height required')
    # Full-source analysis, not separate tile normalisation or per-tile filtering.
    local=gaussian_filter(h,1.0,mode='nearest')
    broad=gaussian_filter(h,3.5,mode='nearest')
    dy,dx=np.gradient(local,cell,cell)
    by,bx=np.gradient(broad,cell,cell)
    light=np.array([-.6,-.8,1.05]);light/=np.linalg.norm(light)
    def shade(gx,gy):return (-gx*light[0]-gy*light[1]+light[2])/np.sqrt(1+gx*gx+gy*gy)-light[2]
    hyx,hxx=np.gradient(dx,cell,cell);hyy,hxy=np.gradient(dy,cell,cell)
    g2=dx*dx+dy*dy
    cross=(dy*dy*hxx-2*dx*dy*(hxy+hyx)*.5+dx*dx*hyy)/np.maximum(g2,1e-5)
    return dict(height=local,light=shade(dx,dy)*.72+shade(bx,by)*.28,slope=np.degrees(np.arctan(np.sqrt(g2))),tpi=local-broad,cross_curvature=cross,dx=dx,dy=dy)

def bilinear(field,x,y,origin=ORIGIN,cell=40):
    u=(x-origin[0])/cell-.5;v=(y-origin[1])/cell-.5
    # Clamp coordinates before splitting integer/fractional parts.
    u=np.clip(u,0,field.shape[1]-1);v=np.clip(v,0,field.shape[0]-1)
    ix=np.floor(u).astype(np.int32);iy=np.floor(v).astype(np.int32)
    fx=u-ix;fy=v-iy;jx=np.minimum(ix+1,field.shape[1]-1);jy=np.minimum(iy+1,field.shape[0]-1)
    return (field[iy,ix]*(1-fx)+field[iy,jx]*fx)*(1-fy)+(field[jy,ix]*(1-fx)+field[jy,jx]*fx)*fy

def render(fields,x,y):
    light=bilinear(fields['light'],x,y)
    tpi=bilinear(fields['tpi'],x,y)
    curvature=bilinear(fields['cross_curvature'],x,y)
    height=bilinear(fields['height'],x,y)
    slope=bilinear(fields['slope'],x,y)
    # Concave/convex terms are landform candidates, not asserted ridge/river IDs.
    valley=np.maximum(0,np.tanh(-tpi/13))
    crest=np.maximum(0,np.tanh(tpi/13))
    curve=np.tanh(curvature*110)*np.clip(slope/18,0,1)
    wash=noise(x,y,125,11)*.64+noise(x,y,35,23)*.36
    grain=(noise(x,y,1.6,19)-.5)*1.4
    illumination=np.clip(light*1.12,-.46,.29)
    # Fixed work-area palette; elevation only warms/cools, never classifies land cover.
    warm=np.clip((height-380)/150,-.4,1)
    channels=[]
    for i,(base,amp) in enumerate([(199,134),(198,129),(165,105)]):
        value=base+illumination*amp-valley*[15,13,8][i]+crest*[7,7,5][i]-curve*[5,6,4][i]
        value+=warm*[5,3,-1][i]+(wash-.5)*[7,7,5][i]+grain
        channels.append(np.clip(value,0,255).astype(np.uint8))
    return Image.fromarray(np.stack(channels,axis=-1))

def grid(bounds,ppm,width,height):
    x=bounds[0]+(np.arange(width)+.5)/ppm;y=bounds[1]+(np.arange(height)+.5)/ppm
    return np.meshgrid(x,y)

def raster(fields,bounds,ppm,width,height):
    image=Image.new('RGB',(width,height))
    for row in range(0,height,128):
        count=min(128,height-row);b=[bounds[0],bounds[1]+row/ppm]
        x,y=grid(b,ppm,width,count);image.paste(render(fields,x,y),(0,row))
    return image

def water_mask(bounds,ppm,width,height):
    mask=Image.new('L',(width,height));draw=ImageDraw.Draw(mask)
    for feature in read(RUNTIME/'bundle/modern_water.json')['features']:
        points=[((p[0]-bounds[0])*ppm,(p[1]-bounds[1])*ppm) for p in feature['points_m']]
        if feature['geometry']=='polygon':draw.polygon(points,fill=255)
        elif len(points)>1:draw.line(points,fill=255,width=max(1,round(2.5*ppm)),joint='curve')
    return mask

def water_raster(bounds,ppm,width,height,mask):
    image=Image.new('RGBA',(width,height))
    for row in range(0,height,128):
        count=min(128,height-row);x,y=grid([bounds[0],bounds[1]+row/ppm],ppm,width,count)
        wash=noise(x,y,120,11)*.58+noise(x,y,38,23)*.28+noise(x,y,7,7)*.14
        n=noise(x,y,80,41)*.7+noise(x,y,12,53)*.3
        ripples=np.sin(x*.15+np.sin(y*.022)*2)*np.sin(y*.19+wash*1.2)
        rgb=np.stack([np.clip(v+(n-.5)*9+ripples*1.4,0,255).astype(np.uint8) for v in [139,176,176]],axis=-1)
        rgba=np.concatenate([rgb,np.asarray(mask.crop((0,row,width,row+count)))[:,:,None]],axis=-1)
        image.paste(Image.fromarray(rgba),(0,row))
    return image

def structure_brush(fields,contours,bounds,ppm,width,height,mask):
    layer=Image.new('RGBA',(width,height));draw=ImageDraw.Draw(layer);used=[];segments=0;hatches=0
    def pixel(p):return ((p[0]-bounds[0])*ppm,(p[1]-bounds[1])*ppm)
    for index,feature in enumerate(contours['features']):
        # A few height breaks only. Complete contour information stays a debug layer.
        if feature['level_m'] not in [350,420,520]:continue
        points=feature['points_m'];length=0;accepted=0
        for a,b in zip(points,points[1:]):
            mid=np.array([(a[0]+b[0])*.5,(a[1]+b[1])*.5]);length+=math.dist(a,b)
            if not bounds[0]-40<=mid[0]<=bounds[0]+width/ppm+40 or not bounds[1]-40<=mid[1]<=bounds[1]+height/ppm+40:continue
            sx,sy=np.array([mid[0]]),np.array([mid[1]])
            slope=float(bilinear(fields['slope'],sx,sy)[0]);tpi=float(bilinear(fields['tpi'],sx,sy)[0])
            if slope<14 or slope>60 or abs(tpi)<1.5:continue
            draw.line([pixel(a),pixel(b)],fill=(91,105,77,38),width=max(1,round(ppm*.9)))
            accepted+=1;segments+=1
            if length>62:
                length=0;dx=float(bilinear(fields['dx'],sx,sy)[0]);dy=float(bilinear(fields['dy'],sx,sy)[0]);n=max(math.hypot(dx,dy),1e-6)
                end=mid-np.array([dx,dy])/n*min(20,7+slope*.30)
                draw.line([pixel(mid),pixel(end)],fill=(98,113,82,28),width=max(1,round(ppm*.7)));hatches+=1
        if accepted:used.append(dict(feature_index=index,level_m=feature['level_m'],segments=accepted))
    alpha=np.array(layer.getchannel('A'));alpha[np.asarray(mask)>0]=0;layer.putalpha(Image.fromarray(alpha))
    return layer,dict(selected_source_features=used,segments=segments,slope_hatches=hatches,selection='levels 350/420/520, slope 14..60deg, abs local TPI>=1.5m',semantics='painted slope structure only; not new terrain geometry')

def main():
    out=DEST/'assets';out.mkdir(parents=True,exist_ok=False)
    h=np.fromfile(RUNTIME/'bundle/elevation_f32.bin',dtype='<f4').reshape(400,600)
    contours=read(RUNTIME/'review/relief_contours.json')
    if sha(RUNTIME/'bundle/elevation_f32.bin')!=contours['source_numeric_sha256']:raise RuntimeError('contour/height mismatch')
    fields=analyze(h,40)
    full=[BOUNDS[0]-GUTTER/2,BOUNDS[1]-GUTTER/2];w=4*CORE+2*GUTTER;hh=3*CORE+2*GUTTER
    reference=raster(fields,full,2,w,hh)
    mask=water_mask(full,2,w,hh);brush,brush_meta=structure_brush(fields,contours,full,2,w,hh,mask)
    reference=Image.alpha_composite(reference.convert('RGBA'),brush).convert('RGB');reference.save(out/'reference_fine.png')
    water=water_raster(full,2,w,hh,mask)
    records=[];checks=[]
    for row in range(3):
        for col in range(4):
            left=BOUNDS[0]+col*512;top=BOUNDS[1]+row*512
            # Independently evaluate one tile for an actual global-vs-tile reference test.
            tile=raster(fields,[left-GUTTER/2,top-GUTTER/2],2,CORE+2*GUTTER,CORE+2*GUTTER)
            brush_tile=brush.crop((col*CORE,row*CORE,col*CORE+CORE+2*GUTTER,row*CORE+CORE+2*GUTTER))
            tile=Image.alpha_composite(tile.convert('RGBA'),brush_tile).convert('RGB')
            ref=reference.crop((col*CORE,row*CORE,col*CORE+CORE+2*GUTTER,row*CORE+CORE+2*GUTTER))
            checks.append(dict(id=f'{col}_{row}',independent_global_equal=np.array_equal(np.asarray(tile),np.asarray(ref))))
            wet=water.crop((col*CORE,row*CORE,col*CORE+CORE+2*GUTTER,row*CORE+CORE+2*GUTTER))
            old=Image.open(RUNTIME/f'v02/v1/assets/terrain_v01/water_{col}_{row}.png')
            checks[-1]['old_water_core_equal']=np.array_equal(np.asarray(wet.crop((GUTTER,GUTTER,GUTTER+CORE,GUTTER+CORE))),np.asarray(old.crop((4,4,4+CORE,4+CORE))))
            for kind,image in [('ground',tile),('water',wet)]:
                path=out/f'{kind}_{col}_{row}.png';image.save(path)
                records.append(dict(kind=kind,path='res://v02/relief_r01/assets/'+path.name,left_m=left,top_m=top,core_px=CORE,gutter_px=GUTTER,ppm=2,sha256=sha(path)))
    # Low-resolution full-source context makes the existing ridges and gullies readable.
    context_bounds=[-12000,-8000,24000,16000];cw,ch=2400,1600
    raster(fields,context_bounds,.1,cw,ch).save(out/'context_ground.png')
    context_mask=water_mask(context_bounds,.1,cw,ch)
    water_raster(context_bounds,.1,cw,ch,context_mask).save(out/'context_water.png')
    scene=['[gd_scene load_steps=27 format=3]']
    all_rows=[dict(kind='ground',path='res://v02/relief_r01/assets/context_ground.png',left_m=-12000,top_m=-8000,core_px=None,ppm=.1),dict(kind='water',path='res://v02/relief_r01/assets/context_water.png',left_m=-12000,top_m=-8000,core_px=None,ppm=.1),*records]
    scene[0]='[gd_scene load_steps=%d format=3]'%(len(all_rows)+1)
    for i,r in enumerate(all_rows):scene.append(f'[ext_resource type="Texture2D" path="{r["path"]}" id="{i+1}"]')
    scene.extend(['[node name="Relief" type="Node2D"]','texture_filter = 2'])
    for i,r in enumerate(all_rows):
        scene.extend([f'[node name="Tile_{i:02}" type="Sprite2D" parent="."]',f'position = Vector2({r["left_m"]}, {r["top_m"]})',f'scale = Vector2({1/r["ppm"]}, {1/r["ppm"]})','centered = false'])
        if r['core_px']:scene.extend(['region_enabled = true',f'region_rect = Rect2({GUTTER}, {GUTTER}, {CORE}, {CORE})','region_filter_clip_enabled = false'])
        scene.append(f'texture = ExtResource("{i+1}")')
    (DEST/'terrain.tscn').write_text('\n'.join(scene)+'\n',encoding='utf-8')
    config=dict(status='candidate_pending_user_review',algorithm='height_normals_multiscale_TPI_cross_curvature_r01',source_height_sha256=sha(RUNTIME/'bundle/elevation_f32.bin'),source_contours_sha256=sha(RUNTIME/'review/relief_contours.json'),source_water_sha256=sha(RUNTIME/'bundle/modern_water.json'),cell_m=40,analysis_sigma_cells=[1,3.5],light=[-.6,-.8,1.05],bounds_m=BOUNDS,core_px=CORE,gutter_px=GUTTER,allowed_mips=[0],reference_path='res://v02/relief_r01/assets/reference_fine.png',reference_rect=[GUTTER,GUTTER,4096,3072],records=records,tests=checks,context={'bounds_m':context_bounds,'pixel_size':[cw,ch]},notes=['TPI/curvature identify candidate landform structure, not historical or hydrological authority','No ground displacement, height-based land-cover classification or tile contrast normalisation','Base-level linear sampling only; no unsupported deep mip claim'])
    save(DEST/'terrain.json',config)
    save(DEST/'structure_brushes.json',brush_meta)
    if not all(r['independent_global_equal'] and r['old_water_core_equal'] for r in checks):raise RuntimeError('terrain or water regression')
    print('RELIEF_PREPARED',len(records),'page layers; 12 independent tile comparisons and unchanged water cores',flush=True)

if __name__=='__main__':main()
