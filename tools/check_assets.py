"""Validate owned release assets with Pillow only; no installed game is needed."""
from pathlib import Path, PurePosixPath
import hashlib,json,struct,zipfile,re
from PIL import Image
import xml.etree.ElementTree as ET
from klei_assets import read_anim,read_build,read_tex,crop_symbol,hash_name,validate_build_symbols
from paths import ROOT,MOD

# These names are deliberately loaded from the installed game at runtime. A
# misspelled or missing project animation must not be accepted as a game asset.
NATIVE_RUNTIME_ANIMATIONS={
    'anim/amulets.zip', 'anim/bishop_attack.zip', 'anim/cane.zip',
    'anim/deer_ice_flakes.zip', 'anim/ghost_wilson_build.zip',
    'anim/wagdrone_laserwire_fx.zip',
}
OWNED_ANIMATION_ARCHIVES={
    'anim/krypton_survivor.zip', 'anim/krypton_staff_build.zip',
    'anim/krypton_flight.zip', 'anim/krypton_eating.zip',
    'anim/krypton_frostbreath_head.zip', 'anim/krypton_starcore_build.zip',
}


def check_asset_references():
    # Compare spellings as POSIX strings so Windows checks also catch filenames
    # that would fail after a case-sensitive Linux checkout.
    distributed={p.relative_to(MOD).as_posix() for p in MOD.rglob('*') if p.is_file()}
    declarations=[]
    pattern=r'''\bAsset\s*\(\s*["'](ANIM|ATLAS|IMAGE)["']\s*,\s*["']([^"']+)["']\s*\)'''
    for path in MOD.rglob('*.lua'):
        for kind,name in re.findall(pattern,path.read_text(encoding='utf8')):
            relative=PurePosixPath(name)
            assert not relative.is_absolute() and '..' not in relative.parts \
                and relative.as_posix()==name,'Invalid asset path: '+name
            assert relative.suffix=={'ANIM':'.zip','ATLAS':'.xml','IMAGE':'.tex'}[kind], \
                'Unexpected asset extension: '+name
            if name in NATIVE_RUNTIME_ANIMATIONS:
                assert kind=='ANIM'
                assert name not in distributed,'Native runtime asset must not be distributed: '+name
            else:
                assert name in distributed, \
                    f'Missing declared local asset (case-sensitive): {name} in {path.relative_to(ROOT)}'
            declarations.append((kind,name))
    archives={name for name in distributed if name.startswith('anim/') and name.endswith('.zip')}
    assert not archives-OWNED_ANIMATION_ARCHIVES, \
        'Unexpected distributed animation archive: '+', '.join(sorted(archives-OWNED_ANIMATION_ARCHIVES))
    assert OWNED_ANIMATION_ARCHIVES<=archives,'Missing owned animation archive'
    return len(declarations)


def check_texture(data):
    assert len(data)>=8,'Texture header is truncated'
    assert data[:4]==b'KTEX'
    header=struct.unpack_from('<I',data,4)[0]
    assert (header>>4)&31==4,'Custom textures must use RGBA'
    count=(header>>13)&31
    assert count>0
    assert len(data)>=8+count*10,'Texture mip table is truncated'
    rows=[struct.unpack_from('<HHHI',data,8+i*10) for i in range(count)]
    assert len(data)==8+count*10+sum(r[3] for r in rows),'Texture data is truncated'
    for i,(w,h,pitch,size) in enumerate(rows):
        assert pitch==w*4 and size==w*h*4
        if i:assert (w,h)==(max(1,rows[i-1][0]//2),max(1,rows[i-1][1]//2))
    assert rows[-1][:2]==(1,1),'Missing mip levels'
    return read_tex(data)

declarations=check_asset_references()
total=0
for archive,name,count in [('krypton_survivor.zip','krypton_survivor',132),
                            ('krypton_staff_build.zip','krypton_staff_build',3)]:
    with zipfile.ZipFile(MOD/'anim'/archive) as z:
        assert set(z.namelist())=={'build.bin','atlas-0.tex'},'Do not bundle vanilla animations'
        build=read_build(z.read('build.bin'));texture=check_texture(z.read('atlas-0.tex'))
        validate_build_symbols(build)
        assert build['name']==name and sum(len(s['frames']) for s in build['symbols'])==count
        for symbol in build['symbols']:
            for row in symbol['frames']:
                verts=build['verts'][row[6]:row[6]+row[7]]
                assert row[4]>0 and row[5]>0 and len(verts)==6
                assert all(0<=v[3]<=1 and 0<=v[4]<=1 and v[5]==0 for v in verts)
                crop_symbol(build,texture,symbol,row[0])
                total+=1
spec=json.loads((ROOT/'assets/slices.json').read_text(encoding='utf8'))
# Generated mouth data must follow the authored source pixels, including mirrors.
frost_data=(MOD/'scripts/krypton_frostbreath_visual_data.lua').read_text(encoding='utf8')
for direction,layout in spec['frostbreath']['mouth_points'].items():
    source=layout.get('inherit',direction)
    head=spec['placement']['head'][source]
    point=spec['frostbreath']['mouth_points'][source]['source_point']
    expected=[(point[i]-head['anchor'][i])*head['scale']+head['local_anchor'][i] for i in range(2)]
    match=re.search(r'%s\s*=\s*\{\s*mouth\s*=\s*\{\s*([-\d.]+),\s*([-\d.]+)' % direction,frost_data)
    assert match is not None,'Missing generated mouth anchor: '+direction
    assert all(abs(float(match.group(i+1))-expected[i])<1e-5 for i in range(2)),'Stale generated mouth: '+direction
flight=spec['flight']
with zipfile.ZipFile(MOD/'anim/krypton_flight.zip') as z:
    assert set(z.namelist())=={'build.bin','atlas-0.tex','anim.bin'},'Flight archive must contain only its own build and animation'
    build=read_build(z.read('build.bin'));texture=check_texture(z.read('atlas-0.tex'))
    validate_build_symbols(build)
    assert build['name']==flight['build'] and len(build['symbols'])==1
    symbol=build['symbols'][0]
    assert symbol['name']==flight['symbol'] and symbol['hash']==hash_name(flight['symbol'])
    assert [row[0] for row in symbol['frames']]==list(range(6))
    for row in symbol['frames']:
        verts=build['verts'][row[6]:row[6]+row[7]]
        assert row[4]>0 and row[5]>0 and len(verts)==6
        assert all(0<=v[3]<=1 and 0<=v[4]<=1 and v[5]==0 for v in verts)
        assert crop_symbol(build,texture,symbol,row[0]).getbbox(),'Missing supplied flight pose'
        total+=1
    animation_data=z.read('anim.bin')
    magic,version,elements,frames,events,count=struct.unpack_from('<4s5I',animation_data)
    assert (magic,version,elements,frames,events,count)==(b'ANIM',4,72,72,0,6)
    animations,names=read_anim(animation_data)
    assert names=={hash_name(flight['bank']):flight['bank'],hash_name(flight['symbol']):flight['symbol']}
    for animation,pose in zip(animations,flight['poses']):
        assert (animation['name'],animation['facing'],animation['root'],animation['rate'])==(
            pose['animation'],pose['facing'],hash_name(flight['bank']),flight['frames_per_second'])
        assert len(animation['frames'])==flight['loop_frames']
        for frame in animation['frames']:
            assert not frame['events'] and len(frame['elements'])==1
            element=frame['elements'][0]
            assert element[:3]==(symbol['hash'],pose['frame'],symbol['hash'])
            assert element[3:8]==(1,0,0,1,0),'Flight animation only translates existing pixels'
            assert abs(element[8])<=flight['bob_pixels']+.001 and element[9]==0
eating=spec['eating']
with zipfile.ZipFile(MOD/'anim/krypton_eating.zip') as z:
    assert set(z.namelist())=={'build.bin','atlas-0.tex'},'Eating build must not bundle native animations'
    build=read_build(z.read('build.bin'));texture=check_texture(z.read('atlas-0.tex'))
    validate_build_symbols(build)
    assert build['name']==eating['build']
    expected={pose['symbol'] for pose in eating['poses']}
    assert {symbol['name'] for symbol in build['symbols']}==expected and len(expected)==3
    for symbol in build['symbols']:
        assert symbol['hash']==hash_name(symbol['name']) and len(symbol['frames'])==1
        row=symbol['frames'][0]
        assert row[0]==0 and row[1]==1 and row[4]>0 and row[5]>0
        verts=build['verts'][row[6]:row[6]+row[7]]
        assert len(verts)==6 and all(0<=v[3]<=1 and 0<=v[4]<=1 and v[5]==0 for v in verts)
        assert crop_symbol(build,texture,symbol,0).getbbox(),'Missing supplied eating head'
        total+=1
    assert eating['frames_per_second']==30
    supported={'eat_pre','eat','eat_lag','quick_eat_pre','quick_eat','quick_eat_lag',
               'quick_drink_pre','quick_drink','quick_drink_lag'}
    assert set(eating['timelines'])<=supported
    poses={pose['pose'] for pose in eating['poses']}
    for animation,timeline in eating['timelines'].items():
        assert timeline
        assert all(isinstance(frame,int) and frame>=0 and pose in poses for frame,pose in timeline)
        assert all(timeline[i][0]<timeline[i+1][0] for i in range(len(timeline)-1))
breath_head=spec['breath_head']
assert breath_head['native_head_frames']==[0,1,2],'Native head requests need front, profile and back coverage'
head_data=(MOD/'scripts/krypton_frostbreath_head_data.lua').read_text(encoding='utf8')
assert 'build = '+json.dumps(breath_head['build']) in head_data
with zipfile.ZipFile(MOD/breath_head['archive']) as z:
    assert set(z.namelist())=={'build.bin','atlas-0.tex'},'Breath heads must not bundle native animations'
    build=read_build(z.read('build.bin'));texture=check_texture(z.read('atlas-0.tex'))
    validate_build_symbols(build)
    assert build['name']==breath_head['build']
    assert texture.size==(breath_head['atlas_size'],)*2
    expected={pose['symbol']:pose for pose in breath_head['poses']}
    assert len(expected)==2 and {s['name'] for s in build['symbols']}==set(expected)
    for symbol in build['symbols']:
        pose=expected[symbol['name']]
        assert symbol['hash']==hash_name(symbol['name']) and len(symbol['frames'])==1
        row=symbol['frames'][0]
        verts=build['verts'][row[6]:row[6]+row[7]]
        assert row[0]==0 and row[4]>0 and row[5]>0 and len(verts)==6
        for frame in breath_head['native_head_frames']:
            assert row[0]<=frame<row[0]+row[1], \
                f"Breath head {symbol['name']} cannot resolve native head frame {frame}"
        assert all(0<=v[3]<=1 and 0<=v[4]<=1 and v[5]==0 for v in verts)
        assert crop_symbol(build,texture,symbol,0).getbbox(),'Missing supplied breath head'
        point=[(pose['mouth_point'][i]-pose['anchor'][i])*pose['scale']+pose['local_anchor'][i] for i in range(2)]
        match=re.search(r'%s\s*=\s*\{\s*symbol\s*=\s*"%s",\s*mouth\s*=\s*\{\s*([-\d.]+),\s*([-\d.]+)' %
                        (pose['pose'],pose['symbol']),head_data)
        assert match is not None,'Missing open-mouth anchor: '+pose['pose']
        assert all(abs(float(match.group(i+1))-point[i])<1e-5 for i in range(2)),'Stale open-mouth anchor'
        assert row[2]-row[4]/2<point[0]<row[2]+row[4]/2
        assert row[3]-row[5]/2<point[1]<row[3]+row[5]/2
        selection=spec['selections'][pose['selection']]
        assert selection['source']=='breath_head'
        assert selection['reference_size']==spec['sources']['breath_head']['reference_size']
        total+=1
ui=spec['hud_icons']
provenance=json.loads((ROOT/'assets/source/ui/prompts-and-provenance.json').read_text(encoding='utf8'))
assert set(ui['icons'])=={'flight','protection','revival'} and ui['size']==[128,128]
for name,item in ui['icons'].items():
    source=ROOT/item['source']
    assert hashlib.sha256(source.read_bytes()).hexdigest()==provenance['assets'][name]['sha256']
    with Image.open(source) as image:
        assert image.mode=='RGBA' and image.getchannel('A').getextrema()==(0,255)
    target=MOD/'images/abilityicons'/item['element']
    icon=check_texture(target.read_bytes())
    assert icon.size==tuple(ui['size']) and icon.getchannel('A').getextrema()==(0,255)
    bounds=icon.getchannel('A').getbbox()
    assert bounds is not None and all(bounds[i+2]-bounds[i]<=ui['fit_size'][i] for i in range(2))
    atlas=ET.fromstring(target.with_suffix('.xml').read_text(encoding='utf8'))
    assert atlas.find('Texture').attrib['filename']==target.name
    assert [el.attrib['name'] for el in atlas.findall('./Elements/Element')]==[item['element']]
starcore=spec['starcore']
with zipfile.ZipFile(MOD/'anim/krypton_starcore_build.zip') as z:
    assert set(z.namelist())=={'build.bin','atlas-0.tex'},'Starcore must not bundle native animations'
    build=read_build(z.read('build.bin'));texture=check_texture(z.read('atlas-0.tex'))
    validate_build_symbols(build)
    assert build['name']==starcore['build'] and len(build['symbols'])==1
    symbol=build['symbols'][0]
    assert symbol['name']==starcore['symbol'] and symbol['hash']==hash_name(starcore['symbol'])
    assert len(symbol['frames'])==1 and symbol['frames'][0][0]==starcore['frame']
    row=symbol['frames'][0]
    verts=build['verts'][row[6]:row[6]+row[7]]
    assert row[1]==1 and row[4]>0 and row[5]>0 and len(verts)==6
    assert all(0<=v[3]<=1 and 0<=v[4]<=1 and v[5]==0 for v in verts)
    assert crop_symbol(build,texture,symbol,starcore['frame']).getbbox(),'Missing supplied starcore'
    total+=1
for p in MOD.rglob('*.tex'):check_texture(p.read_bytes())
for p in MOD.rglob('*.xml'):
    atlas=ET.fromstring(p.read_text(encoding='utf8'))
    texture_node=atlas.find('Texture')
    assert atlas.tag=='Atlas' and texture_node is not None,'Invalid atlas: '+str(p)
    filename=texture_node.attrib['filename']
    assert PurePosixPath(filename).name==filename,'Atlas texture must be a local filename: '+str(p)
    texture=p.parent/filename
    siblings={entry.name for entry in p.parent.iterdir() if entry.is_file()}
    assert filename in siblings and texture.is_file(),'Missing atlas texture: '+str(texture)
    elements=atlas.findall('./Elements/Element')
    names=[element.attrib['name'] for element in elements]
    assert names and all(names) and len(names)==len(set(names)),'Invalid or duplicate atlas elements: '+str(p)
    for element in elements:
        assert 0<=float(element.attrib['u1'])<float(element.attrib['u2'])<=1
        assert 0<=float(element.attrib['v1'])<float(element.attrib['v2'])<=1
for manifest_path in [ROOT/'build/extraction-manifest.json',ROOT/'build/flight-extraction-manifest.json',
                      ROOT/'build/eating-extraction-manifest.json',ROOT/'build/starcore-extraction-manifest.json']:
    if manifest_path.exists():
        for item in json.loads(manifest_path.read_text(encoding='utf8'))['sources'].values():
            assert hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()==item['sha256']
head_manifest=ROOT/'build/frostbreath-head-extraction-manifest.json'
if head_manifest.exists():
    manifest=json.loads(head_manifest.read_text(encoding='utf8'))
    source=manifest['source']
    assert hashlib.sha256((ROOT/source['path']).read_bytes()).hexdigest()==source['sha256']
    assert hashlib.sha256((MOD/breath_head['archive']).read_bytes()).hexdigest()==manifest['archive_sha256']
ui_manifest=ROOT/'build/ability-ui-extraction-manifest.json'
if ui_manifest.exists():
    for item in json.loads(ui_manifest.read_text(encoding='utf8'))['icons'].values():
        assert hashlib.sha256((ROOT/item['source']).read_bytes()).hexdigest()==item['sha256']
print(f'Validated {total} symbol frames, {declarations} asset declarations, full texture mip chains, UI atlases and available source hashes.')
