#!/usr/bin/env python3
"""Stream and verify NVIDIA BSP; extract its unmodified kernel and fTPM module."""
import urllib.request,hashlib,tarfile,pathlib,shutil,subprocess,sys
url='https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.2/releases/Jetson_Linux_r36.5.2_aarch64.tbz2'
out=pathlib.Path(__file__).resolve().parents[1]/'work/ftpm-virt'
out.mkdir(parents=True,exist_ok=True)
h=hashlib.sha256()
class Reader:
 def __init__(self,f):self.f=f
 def read(self,n=-1):
  d=self.f.read(n);h.update(d);return d
with urllib.request.urlopen(url,timeout=120) as response:
 r=Reader(response)
 with tarfile.open(fileobj=r,mode='r|bz2') as t:
  for m in t:
   if m.name in ['Linux_for_Tegra/kernel/Image','Linux_for_Tegra/kernel/kernel_supplements.tbz2']:
    print(m.name,m.size,flush=True)
    with (out/pathlib.Path(m.name).name).open('wb') as dest:shutil.copyfileobj(t.extractfile(m),dest)
 while r.read(1024*1024):pass
print('BSP SHA-256',h.hexdigest(),flush=True)
assert h.hexdigest()=='752326264c5e16826d3044a78e59ae06109467d37705143b94e664c91a471f47'

# Extract only regular files, retaining paths relative to the module root.
with tarfile.open(out/'kernel_supplements.tbz2', 'r:bz2') as archive:
 for m in archive:
  relative = pathlib.PurePosixPath(m.name.removeprefix('./'))
  if '..' in relative.parts or relative.is_absolute():
   raise SystemExit('Unsafe archive path')
  if m.isfile() and (relative.name in ('modules.builtin', 'modules.builtin.modinfo') or relative.name == 'tpm_ftpm_tee.ko'):
   target = out/'modules'/relative
   target.parent.mkdir(parents=True,exist_ok=True)
   with target.open('wb') as f:
    shutil.copyfileobj(archive.extractfile(m), f)

subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("install-artifacts.py")), "kernel"],check=True)
