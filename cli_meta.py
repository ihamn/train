#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cli_meta.py - 纯 stdlib 的 ECMA-335 CLI 元数据 + IL 解析器。
用于在没有 dotnet/mono 运行时的环境解析 Unity Mono 托管程序集。"""
import struct, sys, os, json

class PE:
    def __init__(self, data):
        self.d = data
        pe = struct.unpack_from('<I', data, 0x3c)[0]
        coff = pe + 4
        self.nsec = struct.unpack_from('<H', data, coff + 2)[0]
        optsz  = struct.unpack_from('<H', data, coff + 16)[0]
        opt = coff + 20
        self.magic = struct.unpack_from('<H', data, opt)[0]
        ddir = opt + (96 if self.magic == 0x10b else 112)
        self.clr_rva, self.clr_sz = struct.unpack_from('<II', data, ddir + 14*8)
        self.secs = []
        so = opt + optsz
        for i in range(self.nsec):
            b = so + 40*i
            name = data[b:b+8].rstrip(b'\0').decode('latin1')
            vsz, va, rsz, ra = struct.unpack_from('<IIII', data, b+8)
            self.secs.append((name, va, vsz, ra, rsz))
    def rva2off(self, rva):
        for name, va, vsz, ra, rsz in self.secs:
            if va <= rva < va + max(vsz, rsz):
                return ra + (rva - va)
        return None

TABLES = [
 ('Module',[('Generation','u2'),('Name','str'),('Mvid','guid'),('EncId','guid'),('EncBaseId','guid')]),
 ('TypeRef',[('ResolutionScope','coded:ResolutionScope'),('Name','str'),('Namespace','str')]),
 ('TypeDef',[('Flags','u4'),('Name','str'),('Namespace','str'),('Extends','coded:TypeDefOrRef'),('FieldList','list:Field'),('MethodList','list:MethodDef')]),
 ('FieldPtr',[('Field','rid:Field')]),
 ('Field',[('Flags','u2'),('Name','str'),('Signature','blob')]),
 ('MethodPtr',[('Method','rid:MethodDef')]),
 ('MethodDef',[('RVA','u4'),('ImplFlags','u2'),('Flags','u2'),('Name','str'),('Signature','blob'),('ParamList','list:Param')]),
 ('ParamPtr',[('Param','rid:Param')]),
 ('Param',[('Flags','u2'),('Sequence','u2'),('Name','str')]),
 ('InterfaceImpl',[('Class','rid:TypeDef'),('Interface','coded:TypeDefOrRef')]),
 ('MemberRef',[('Class','coded:MemberRefParent'),('Name','str'),('Signature','blob')]),
 ('Constant',[('Type','u2'),('Padding','u2'),('Parent','coded:HasConstant'),('Value','blob')]),
 ('CustomAttribute',[('Parent','coded:HasCustomAttribute'),('Type','coded:CustomAttributeType'),('Value','blob')]),
 ('FieldMarshal',[('Parent','coded:HasFieldMarshal'),('NativeType','blob')]),
 ('DeclSecurity',[('Action','u2'),('Parent','coded:HasDeclSecurity'),('PermissionSet','blob')]),
 ('ClassLayout',[('PackingSize','u2'),('ClassSize','u4'),('Parent','rid:TypeDef')]),
 ('FieldLayout',[('Offset','u4'),('Field','rid:Field')]),
 ('StandAloneSig',[('Signature','blob')]),
 ('EventMap',[('Parent','rid:TypeDef'),('EventList','list:Event')]),
 ('EventPtr',[('Event','rid:Event')]),
 ('Event',[('EventFlags','u2'),('Name','str'),('EventType','coded:TypeDefOrRef')]),
 ('PropertyMap',[('Parent','rid:TypeDef'),('PropertyList','list:Property')]),
 ('PropertyPtr',[('Property','rid:Property')]),
 ('Property',[('Flags','u2'),('Name','str'),('Type','blob')]),
 ('MethodSemantics',[('Semantics','u2'),('Method','rid:MethodDef'),('Association','coded:HasSemantics')]),
 ('MethodImpl',[('Class','rid:TypeDef'),('MethodBody','coded:MethodDefOrRef'),('MethodDeclaration','coded:MethodDefOrRef')]),
 ('ModuleRef',[('Name','str')]),
 ('TypeSpec',[('Signature','blob')]),
 ('ImplMap',[('MappingFlags','u2'),('MemberForwarded','coded:MemberForwarded'),('ImportName','str'),('ImportScope','rid:ModuleRef')]),
 ('FieldRVA',[('RVA','u4'),('Field','rid:Field')]),
 ('EncLog',[('Token','u4'),('FuncCode','u4')]),
 ('EncMap',[('Token','u4')]),
 ('Assembly',[('HashAlgId','u4'),('MajorVersion','u2'),('MinorVersion','u2'),('BuildNumber','u2'),('RevisionNumber','u2'),('Flags','u4'),('PublicKey','blob'),('Name','str'),('Culture','str')]),
 ('AssemblyProcessor',[('Processor','u4')]),
 ('AssemblyOS',[('OSPlatformID','u4'),('OSMajorVersion','u4'),('OSMinorVersion','u4')]),
 ('AssemblyRef',[('MajorVersion','u2'),('MinorVersion','u2'),('BuildNumber','u2'),('RevisionNumber','u2'),('Flags','u4'),('PublicKeyOrToken','blob'),('Name','str'),('Culture','str'),('HashValue','blob')]),
 ('AssemblyRefProcessor',[('Processor','u4'),('AssemblyRef','rid:AssemblyRef')]),
 ('AssemblyRefOS',[('OSPlatformID','u4'),('OSMajorVersion','u4'),('OSMinorVersion','u4'),('AssemblyRef','rid:AssemblyRef')]),
 ('File',[('Flags','u4'),('Name','str'),('HashValue','blob')]),
 ('ExportedType',[('Flags','u4'),('TypeDefId','u4'),('TypeName','str'),('TypeNamespace','str'),('Implementation','coded:Implementation')]),
 ('ManifestResource',[('Offset','u4'),('Flags','u4'),('Name','str'),('Implementation','coded:Implementation')]),
 ('NestedClass',[('NestedClass','rid:TypeDef'),('EnclosingClass','rid:TypeDef')]),
 ('GenericParam',[('Number','u2'),('Flags','u2'),('Owner','coded:TypeOrMethodDef'),('Name','str')]),
 ('MethodSpec',[('Method','coded:MethodDefOrRef'),('Instantiation','blob')]),
 ('GenericParamConstraint',[('Owner','rid:GenericParam'),('Constraint','coded:TypeDefOrRef')]),
]
TIDX = {n:i for i,(n,_) in enumerate(TABLES)}
CODED = {
 'TypeDefOrRef':(['TypeDef','TypeRef','TypeSpec'],2),
 'HasConstant':(['Field','Param','Property'],2),
 'HasCustomAttribute':(['MethodDef','Field','TypeRef','TypeDef','Param','InterfaceImpl','MemberRef','Module','DeclSecurity','Property','Event','StandAloneSig','ModuleRef','TypeSpec','Assembly','AssemblyRef','File','ExportedType','ManifestResource','GenericParam','GenericParamConstraint','MethodSpec'],5),
 'HasFieldMarshal':(['Field','Param'],1),
 'HasDeclSecurity':(['TypeDef','MethodDef','Assembly'],2),
 'MemberRefParent':(['TypeDef','TypeRef','ModuleRef','MethodDef','TypeSpec'],3),
 'HasSemantics':(['Event','Property'],1),
 'MethodDefOrRef':(['MethodDef','MemberRef'],1),
 'MemberForwarded':(['Field','MethodDef'],1),
 'Implementation':(['File','AssemblyRef','ExportedType'],2),
 'CustomAttributeType':(['<none>','<none>','MethodDef','MemberRef','<none>'],3),
 'ResolutionScope':(['Module','ModuleRef','AssemblyRef','TypeRef'],2),
 'TypeOrMethodDef':(['TypeDef','MethodDef'],1),
}

def cint(b, i):
    x = b[i]
    if x & 0x80 == 0: return x, i+1
    if x & 0xC0 == 0x80: return ((x & 0x3F) << 8) | b[i+1], i+2
    return ((x & 0x1F) << 24) | (b[i+1] << 16) | (b[i+2] << 8) | b[i+3], i+4

class Assembly:
    def __init__(self, path):
        self.path = path
        self.data = open(path,'rb').read()
        self.pe = PE(self.data)
        o = self.pe.rva2off(self.pe.clr_rva)
        cb, maj, minr, md_rva, md_sz = struct.unpack_from('<IHHII', self.data, o)
        self.runtime = '%d.%d' % (maj, minr)
        self.entrypoint = struct.unpack_from('<I', self.data, o+20)[0]
        mo = self.pe.rva2off(md_rva)
        self.md_off, self.md_size = mo, md_sz
        self._root(mo); self._tables(); self._nested = None
    def _root(self, mo):
        d = self.data
        assert d[mo:mo+4] == b'BSJB', 'bad metadata sig'
        self.vlen = struct.unpack_from('<I', d, mo+12)[0]
        self.version_string = d[mo+16:mo+16+self.vlen].split(b'\0')[0].decode('latin1')
        n = struct.unpack_from('<H', d, mo+18+self.vlen)[0]
        p = mo + 20 + ((self.vlen + 3) // 4) * 4
        self.streams = {}
        for _ in range(n):
            off, sz = struct.unpack_from('<II', d, p)
            nm = d[p+8:p+40].split(b'\0')[0].decode('ascii')
            self.streams[nm] = (mo+off, sz)
            p += 8 + (((len(nm)+1)+3)//4)*4
        for k in ('#~','#Strings','#US','#Blob','#GUID'):
            self.streams.setdefault(k, (None,0))
    def heap(self, n):
        o,sz = self.streams[n]
        return self.data[o:o+sz] if o is not None else b''
    def string(self, i):
        s = self.heap('#Strings')
        if i >= len(s): return '<str#%d>' % i
        e = s.find(b'\0', i)
        return s[i:e].decode('utf-8','replace')
    def blob(self, i):
        b = self.heap('#Blob')
        if i == 0 or i >= len(b): return b''
        n,p = cint(b,i); return b[p:p+n]
    def user_string(self, i):
        b = self.heap('#US')
        if i == 0 or i >= len(b): return None
        n,p = cint(b,i)
        raw = b[p:p+n]
        if n and n % 2 == 1: raw = raw[:-1]
        try: return raw.decode('utf-16-le')
        except Exception: return None
    def _sz(self, kind):
        if kind=='u2': return 2
        if kind=='u4': return 4
        if kind=='str': return 4 if self.hs & 1 else 2
        if kind=='guid': return 4 if self.hs & 2 else 2
        if kind=='blob': return 4 if self.hs & 4 else 2
        if kind.startswith('rid:'): return 4 if self.rows.get(kind[4:],0) >= 0x10000 else 2
        if kind.startswith('list:'): return 4 if self.rows.get(kind[5:],0) >= 0x10000 else 2
        if kind.startswith('coded:'):
            tabs,bits = CODED[kind[6:]]
            mx = max([self.rows.get(t,0) for t in tabs if not t.startswith('<')] or [0])
            return 4 if mx >= (1 << (16-bits)) else 2
        raise ValueError(kind)
    def _tables(self):
        d = self.data
        o,_ = self.streams['#~']
        self.hs = d[o+6]
        self.valid, self.sorted = struct.unpack_from('<QQ', d, o+8)
        p = o+0x18
        self.rows = {}
        for i,(n,_) in enumerate(TABLES):
            if self.valid & (1<<i):
                self.rows[n] = struct.unpack_from('<I', d, p)[0]; p += 4
        self.table = {}
        for i,(n,cols) in enumerate(TABLES):
            if not (self.valid & (1<<i)): continue
            out = []
            for _r in range(self.rows[n]):
                row = []
                for _cn,kind in cols:
                    if kind=='u2': row.append(struct.unpack_from('<H',d,p)[0]); p+=2
                    elif kind=='u4': row.append(struct.unpack_from('<I',d,p)[0]); p+=4
                    else:
                        s = self._sz(kind)
                        row.append(struct.unpack_from('<H' if s==2 else '<I',d,p)[0]); p+=s
                out.append(row)
            self.table[n] = out
    def cols(self,t): return [c for c,_ in TABLES[TIDX[t]][1]]
    def cell(self,t,r,c): return self.table[t][r-1][self.cols(t).index(c)]
    def coded(self,t,r,c):
        kind = dict(TABLES[TIDX[t]][1])[c]
        tabs,bits = CODED[kind[6:]]
        raw = self.cell(t,r,c); tag = raw & ((1<<bits)-1); rr = raw >> bits
        if tag >= len(tabs) or rr == 0 or tabs[tag].startswith('<'): return None,0
        return tabs[tag], rr
    def tname(self,r):   return self.string(self.cell('TypeDef',r,'Name'))
    def tns(self,r):     return self.string(self.cell('TypeDef',r,'Namespace'))
    def type_full(self,r):
        ns = self.tns(r); n = self.tname(r)
        return (ns+'.'+n) if ns else n
    def typeref_full(self,r):
        ns = self.cell('TypeRef',r,'Namespace'); n = self.cell('TypeRef',r,'Name')
        return (ns+'.'+n) if ns else n
    def method_range(self,r):
        s = self.cell('TypeDef',r,'MethodList')
        e = self.cell('TypeDef',r+1,'MethodList') if r < self.rows['TypeDef'] else self.rows.get('MethodDef',0)+1
        return (e,s) if s==0 else (s,e)
    def field_range(self,r):
        s = self.cell('TypeDef',r,'FieldList')
        e = self.cell('TypeDef',r+1,'FieldList') if r < self.rows['TypeDef'] else self.rows.get('Field',0)+1
        return (e,s) if s==0 else (s,e)
    def owner_of_method(self,r):
        for t in range(1,self.rows['TypeDef']+1):
            s,e = self.method_range(t)
            if s <= r < e: return t
        return 0
    def method_name(self,r): return self.string(self.cell('MethodDef',r,'Name'))
    def method_full(self,r):
        t = self.owner_of_method(r)
        return '%s::%s' % (self.type_full(t), self.method_name(r)) if t else '?::'+self.method_name(r)
    def nested_map(self):
        if self._nested is None:
            self._nested = {}
            for r in range(1,self.rows.get('NestedClass',0)+1):
                self._nested[self.cell('NestedClass',r,'NestedClass')] = self.cell('NestedClass',r,'EnclosingClass')
        return self._nested
    def display_type(self,r):
        nm = self.nested_map(); parts=[]; cur=r; g=0
        while cur and g<32:
            parts.append(self.string(self.cell('TypeDef',cur,'Name'))); cur = nm.get(cur,0); g+=1
        ns = self.tns(r); body = '.'.join(reversed(parts))
        return (ns+'.'+body) if ns else body
    def method_body(self,r):
        rva = self.cell('MethodDef',r,'RVA')
        if rva == 0: return None
        o = self.pe.rva2off(rva)
        if o is None: return None
        d = self.data; b0 = d[o]
        if b0 & 3 == 2:
            size = b0 >> 2; code_off = o+1; flags = (struct.unpack_from('<H',d,o)[0] >> 12) & 0xF
        else:
            flags, lsize = struct.unpack_from('<HH',d,o); hsize = (flags >> 12)*4
            code_off = o+hsize; size = lsize
        return {'flags':flags,'code_size':size,'code':d[code_off:code_off+size]}

OPERANDS = dict((i,0) for i in range(256))
for _o in (0x20,0x21,0x22,0x28,0x29,0x38,0x39,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F,0x40,0x41,0x42,0x43,0x44,
           0x6F,0x70,0x71,0x72,0x73,0x74,0x75,0x79,0x7B,0x7C,0x7D,0x7E,0x7F,0x80,0x81,0x83,
           0x85,0x86,0x87,0x88,0x89,0x8A,0x8B,0x8C,0x8D,0x8E,0x8F,0x90,0x91,0x92,0x93,0x94,
           0x95,0x96,0x97,0x98,0x99,0x9A,0x9B,0x9C,0x9D,0xA3,0xA4,0xA5,0xA6,0xA7,0xA8,0xA9,
           0xAA,0xAB,0xC2,0xC6,0xD0,0xDD): OPERANDS[_o] = 4
for _o in (0x23,0x4A,0x4B,0x4C,0x4D,0x4E,0x4F,0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,
           0x5A,0x5B,0x5C,0x5D,0x5E,0x5F,0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,
           0x6B,0x6C,0x6D,0x6E): OPERANDS[_o] = 8
for _o in (0x0E,0x0F,0x10,0x11,0x12,0x13,0x1F,0x2B,0x2C,0x2D,0x2E,0x2F,0x30,0x31,0x32,0x33,0x34,
           0x35,0x36,0x37,0xDE): OPERANDS[_o] = 1
OPERANDS[0x45] = -1

OPNAME = {
 0x00:'nop',0x01:'break',0x02:'ldarg.0',0x03:'ldarg.1',0x04:'ldarg.2',0x05:'ldarg.3',
 0x06:'ldloc.0',0x07:'ldloc.1',0x08:'ldloc.2',0x09:'ldloc.3',0x0A:'stloc.0',0x0B:'stloc.1',
 0x0C:'stloc.2',0x0D:'stloc.3',0x0E:'ldarg.s',0x0F:'ldarga.s',0x10:'starg.s',0x11:'ldloc.s',
 0x12:'ldloca.s',0x13:'stloc.s',0x14:'ldnull',0x15:'ldc.i4.m1',0x16:'ldc.i4.0',0x17:'ldc.i4.1',
 0x18:'ldc.i4.2',0x19:'ldc.i4.3',0x1A:'ldc.i4.4',0x1B:'ldc.i4.5',0x1C:'ldc.i4.6',0x1D:'ldc.i4.7',
 0x1E:'ldc.i4.8',0x1F:'ldc.i4.s',0x20:'ldc.i4',0x21:'ldc.i8',0x22:'ldc.r4',0x23:'ldc.r8',
 0x25:'dup',0x26:'pop',0x27:'jmp',0x28:'call',0x29:'calli',0x2A:'ret',0x2B:'br.s',0x2C:'brfalse.s',
 0x2D:'brtrue.s',0x2E:'beq.s',0x2F:'bge.s',0x30:'bgt.s',0x31:'ble.s',0x32:'blt.s',0x33:'bne.un.s',
 0x34:'bge.un.s',0x35:'bgt.un.s',0x36:'ble.un.s',0x37:'blt.un.s',0x38:'br',0x39:'brfalse',
 0x3A:'brtrue',0x3B:'beq',0x3C:'bge',0x3D:'bgt',0x3E:'ble',0x3F:'blt',0x40:'bne.un',0x41:'bge.un',
 0x42:'bgt.un',0x43:'ble.un',0x44:'blt.un',0x45:'switch',0x46:'ldind.i1',0x47:'ldind.u1',
 0x48:'ldind.i2',0x49:'ldind.u2',0x4A:'ldind.i4',0x4B:'ldind.u4',0x4C:'ldind.i8',0x4D:'ldind.i',
 0x4E:'ldind.r4',0x4F:'ldind.r8',0x50:'ldind.ref',0x51:'stind.ref',0x52:'stind.i1',0x53:'stind.i2',
 0x54:'stind.i4',0x55:'stind.i8',0x56:'stind.r4',0x57:'stind.r8',0x58:'add',0x59:'sub',0x5A:'mul',
 0x5B:'div',0x5C:'div.un',0x5D:'rem',0x5E:'rem.un',0x5F:'and',0x60:'or',0x61:'xor',0x62:'shl',
 0x63:'shr',0x64:'shr.un',0x65:'neg',0x66:'not',0x67:'conv.i1',0x68:'conv.i2',0x69:'conv.i4',
 0x6A:'conv.i8',0x6B:'conv.r4',0x6C:'conv.r8',0x6D:'conv.u4',0x6E:'conv.u8',0x6F:'callvirt',
 0x70:'cpobj',0x71:'ldobj',0x72:'ldstr',0x73:'newobj',0x74:'castclass',0x75:'isinst',0x76:'conv.r.un',
 0x79:'unbox',0x7A:'throw',0x7B:'ldfld',0x7C:'ldflda',0x7D:'stfld',0x7E:'ldsfld',0x7F:'ldsflda',
 0x80:'stsfld',0x81:'stobj',0x82:'conv.ovf.i1.un',0x83:'conv.ovf.i2.un',0x84:'box',0x85:'newarr',
 0x86:'ldlen',0x87:'ldelema',0x88:'ldelem.i1',0x89:'ldelem.u1',0x8A:'ldelem.i2',0x8B:'ldelem.u2',
 0x8C:'ldelem.i4',0x8D:'ldelem.u4',0x8E:'ldelem.i8',0x8F:'ldelem.i',0x90:'ldelem.r4',0x91:'ldelem.r8',
 0x92:'ldelem.ref',0x93:'stelem.i',0x94:'stelem.i1',0x95:'stelem.i2',0x96:'stelem.i4',0x97:'stelem.i8',
 0x98:'stelem.r4',0x99:'stelem.r8',0x9A:'stelem.ref',0x9B:'ldelem.any',0x9C:'stelem.any',
 0x9D:'unbox.any',0xA3:'ldsfld',0xA4:'ldsflda',0xA5:'stsfld',0xA6:'ldfld',0xA7:'ldflda',0xA8:'stfld',
 0xA9:'ldfld',0xAA:'ldflda',0xAB:'stfld',
 0xB3:'conv.ovf.i1',0xB4:'conv.ovf.u1',0xB5:'conv.ovf.i2',0xB6:'conv.ovf.u2',0xB7:'conv.ovf.i4',
 0xB8:'conv.ovf.u4',0xB9:'conv.ovf.i8',0xBA:'conv.ovf.u8',0xC2:'refanyval',0xC3:'ckfinite',
 0xC6:'mkrefany',0xD0:'ldtoken',0xD1:'conv.u2',0xD2:'conv.u1',0xD3:'conv.i',0xD4:'conv.ovf.i',
 0xD5:'conv.ovf.u',0xD6:'add.ovf',0xD7:'add.ovf.un',0xD8:'mul.ovf',0xD9:'mul.ovf.un',
 0xDA:'sub.ovf',0xDB:'sub.ovf.un',0xDC:'endfinally',0xDD:'leave',0xDE:'leave.s',0xDF:'stind.i',
 0xE0:'conv.u',
}
OPNAME2 = {0x00:'arglist',0x01:'ceq',0x02:'cgt',0x03:'cgt.un',0x04:'clt',0x05:'clt.un',0x06:'ldftn',
 0x07:'ldvirtftn',0x09:'ldarg',0x0A:'ldarga',0x0B:'starg',0x0C:'ldloc',0x0D:'ldloca',0x0E:'stloc',
 0x0F:'localloc',0x11:'endfilter',0x12:'unaligned.',0x13:'volatile.',0x14:'tail.',0x15:'initobj',
 0x16:'constrained.',0x17:'cpblk',0x18:'initblk',0x19:'no.',0x1A:'rethrow',0x1C:'sizeof',0x1D:'refanytype',
 0x1E:'readonly.'}
OPERANDS2 = {0x06:4,0x07:4,0x09:2,0x0A:2,0x0B:2,0x0C:2,0x0D:2,0x0E:2,0x12:1,0x13:1,0x14:1,0x15:4,
 0x16:4,0x19:1,0x1C:4}

def decode_il(code):
    out=[]; i=0; n=len(code)
    while i < n:
        st=i; op=code[i]; i+=1
        if op == 0xFE:
            if i>=n: break
            o2=code[i]; i+=1
            nm=OPNAME2.get(o2,'fe%02x'%o2); s=OPERANDS2.get(o2,0)
            v=code[i:i+s]; i+=s; out.append((st,nm,v,i-st)); continue
        nm=OPNAME.get(op,'op%02x'%op)
        if op == 0x45:
            cnt=struct.unpack_from('<I',code,i)[0]; i+=4
            v=code[i:i+cnt*4]; i+=cnt*4; out.append((st,'switch',v,i-st)); continue
        s=OPERANDS.get(op,0)
        if s<0: s=0
        v=code[i:i+s]; i+=s; out.append((st,nm,v,i-st))
    return out

def token_str(a, tok):
    t=(tok>>24)&0xFF; r=tok&0xFFFFFF
    try:
        if t==0x70:
            s=a.user_string(r); return None if s is None else '"%s"' % s
        if t==0x0A: return a.method_full(r)
        if t==0x06: return a.display_type(r)
        if t==0x01: return a.typeref_full(r)
        if t==0x04: return 'Field#%d' % r
        if t==0x2B: return 'MethodSpec#%d' % r
        if t in (0x1B,0x0B): return 'TypeSpec#%d' % r
    except Exception as e:
        return '<tok %#x err %s>' % (tok,e)
    return '<tok %#010x>' % tok

def method_strings(a, r):
    b=a.method_body(r)
    if not b or not b['code']: return []
    res=[]
    for _o,nm,v,_s in decode_il(b['code']):
        if nm=='ldstr' and len(v)==4:
            s=a.user_string(struct.unpack('<I',v)[0] & 0xFFFFFF)
            if s is not None: res.append(s)
    return res

def method_calls(a, r):
    b=a.method_body(r)
    if not b or not b['code']: return []
    res=[]
    for _o,nm,v,_s in decode_il(b['code']):
        if nm in ('call','callvirt','newobj','ldftn') and len(v)==4:
            res.append((nm, token_str(a, struct.unpack('<I',v)[0])))
    return res

def iter_methods(a):
    for t in range(1,a.rows.get('TypeDef',0)+1):
        s,e=a.method_range(t)
        for m in range(s,e): yield t,m

if __name__ == '__main__':
    a = Assembly(sys.argv[1])
    print('%s runtime=%s ver=%s types=%d methods=%d fields=%d us=%dB' % (
        os.path.basename(sys.argv[1]), a.runtime, a.version_string,
        a.rows.get('TypeDef',0), a.rows.get('MethodDef',0), a.rows.get('Field',0), a.streams['#US'][1]))
