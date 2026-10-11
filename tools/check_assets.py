"""Validate compiled files and provenance without needing a running game."""
from pathlib import Path
import hashlib,json,struct,zipfile
import xml.etree.ElementTree as ET
from klei_assets import read_anim,read_build,read_tex,crop_symbol,hash_name,validate_build_symbols
from paths import ROOT,MOD

def check_texture(data):
    assert data[:4]==b'KTEX'
    header=struct.unpack_from('<I',data,4)[0]
    assert (header>>4)&31==4,'Custom textures must use RGBA'
    count=(header>>13)&31
    assert count>0
    rows=[struct.unpack_from('<HHHI',data,8+i*10) for i in range(count)]
    assert len(data)==8+count*10+sum(r[3] for r in rows),'Texture data is truncated'
    for i,(w,h,pitch,size) in enumerate(rows):
        assert pitch==w*4 and size==w*h*4
        if i:assert (w,h)==(max(1,rows[i-1][0]//2),max(1,rows[i-1][1]//2))
    assert rows[-1][:2]==(1,1),'Missing mip levels'
    return read_tex(data)

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
    texture=p.parent/atlas.find('Texture').attrib['filename']
    assert texture.is_file(),p
    for element in atlas.findall('./Elements/Element'):
        assert 0<=float(element.attrib['u1'])<float(element.attrib['u2'])<=1
        assert 0<=float(element.attrib['v1'])<float(element.attrib['v2'])<=1
for manifest_path in [ROOT/'build/extraction-manifest.json',ROOT/'build/flight-extraction-manifest.json',
                      ROOT/'build/eating-extraction-manifest.json',ROOT/'build/starcore-extraction-manifest.json']:
    if manifest_path.exists():
        for item in json.loads(manifest_path.read_text(encoding='utf8'))['sources'].values():
            assert hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()==item['sha256']
print(f'Validated {total} symbol frames, full texture mip chains, UI atlases and available source hashes.')
