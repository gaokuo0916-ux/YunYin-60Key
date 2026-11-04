"""Read-only source -> different new file. Never overwrite the user's container."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,struct,uuid
LEGACY=32*1024*1024;EXTENDED=256*1024*1024
def crc16(b):
 c=65535
 for v in b:
  c^=v<<8
  for _ in range(8):c=((c<<1)^(0x1021 if c&32768 else 0))&65535
 return c
def extension_header():
 b=bytearray(512);b[:8]=b'YY26RECS'
 struct.pack_into('<IIIIIHH',b,8,1,524288,65538,65664,22890,20,2)
 c=crc16(b[:508]);struct.pack_into('<HH',b,508,c,c^65535);return bytes(b)
def digest_prefix(path,length):
 h=hashlib.sha256()
 with path.open('rb')as f:
  while length:
   b=f.read(min(1024*1024,length))
   if not b:raise ValueError('源文件不完整')
   h.update(b);length-=len(b)
 return h.hexdigest()
def prepare(source,output):
 source=Path(source).resolve(strict=True);output=Path(output).resolve()
 if source==output or output.exists():raise ValueError('输出必须是不同路径且尚不存在的新文件；禁止覆盖旧容器')
 size=source.stat().st_size
 if size not in [LEGACY,EXTENDED]:raise ValueError('源文件须为32MiB旧容器或已扩展的256MiB容器')
 with source.open('rb')as f:
  marker=f.read(16)
 if marker[:8]!=b'YY24STOR' or struct.unpack_from('<II',marker,8)!=(1,65536):raise ValueError('源文件不是兼容的云音存储容器')
 if size==EXTENDED:
  with source.open('rb')as f:
   f.seek(LEGACY);a=f.read(512);b=f.read(512)
  if a!=extension_header() and b!=extension_header():raise ValueError('扩展标记损坏；拒绝将其作为可用新格式克隆')
 output.parent.mkdir(parents=True,exist_ok=True)
 if shutil.disk_usage(output.parent).free<EXTENDED+16*1024*1024:raise ValueError('输出盘空间不足')
 source_hash=digest_prefix(source,size);temporary=output.with_name(output.name+'.partial-'+uuid.uuid4().hex)
 try:
  with source.open('rb')as src,temporary.open('xb')as dst:
   shutil.copyfileobj(src,dst,1024*1024)
   if size==LEGACY:
    header=extension_header();dst.write(header);dst.write(header)
    zeros=bytes(1024*1024);left=EXTENDED-dst.tell()
    while left:
     block=zeros[:min(left,len(zeros))];dst.write(block);left-=len(block)
   dst.flush();os.fsync(dst.fileno())
  if temporary.stat().st_size!=EXTENDED or digest_prefix(temporary,size)!=source_hash:raise ValueError('新文件旧区核对失败，未交付')
  if digest_prefix(source,size)!=source_hash:raise ValueError('读取期间源文件发生变化，未交付')
  # A 256MiB source is cloned exactly; an existing directory is never reset.
  if size==EXTENDED and digest_prefix(temporary,EXTENDED)!=source_hash:raise ValueError('扩展容器克隆核对失败')
  if output.exists():raise ValueError('输出文件已出现，拒绝覆盖')
  temporary.rename(output)
  return {'source':str(source),'output':str(output),'source_bytes':size,'output_bytes':EXTENDED,
   'preserved_source_sha256':source_hash,'old_region_bytes_preserved':size,'new_slots':20,'max_seconds':120,
   'physical_contiguity_verified':False,'note':'保留原文件。新文件放卡根目录时须命名YUNYIN.BIN；固件会核对连续FAT32分配。'}
 finally:
  if temporary.exists():temporary.unlink()
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',required=True);p.add_argument('--output',required=True);a=p.parse_args()
 print(json.dumps(prepare(a.source,a.output),ensure_ascii=False,indent=2))
