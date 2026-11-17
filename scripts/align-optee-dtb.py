#!/usr/bin/env python3
"""Align the early OP-TEE 64-bit ASLR seed read using a valid FDT_NOP token."""
import argparse
from pathlib import Path
import struct


def align_seed(data):
    fields=list(struct.unpack_from('>10I',data))
    if fields[0] != 0xd00dfeed or fields[1] != len(data):
        raise ValueError('Invalid DTB header/size')
    offset=fields[2]
    names=fields[3]
    stack=[]
    while offset < fields[2]+fields[9]:
        token_offset=offset
        token=struct.unpack_from('>I',data,offset)[0];offset+=4
        if token == 1:
            end=data.index(b'\0',offset)
            stack.append(data[offset:end].decode())
            offset=(end+4)&~3
        elif token == 2:
            stack.pop()
        elif token == 3:
            length,name_offset=struct.unpack_from('>II',data,offset);offset+=8
            end=data.index(b'\0',names+name_offset)
            name=data[names+name_offset:end]
            if stack==['','secure-chosen'] and name==b'kaslr-seed':
                if length != 8:raise ValueError('ASLR seed must be 64 bits')
                if offset % 8 == 0:return data,False
                # A NOP before the property shifts its data by four bytes.
                result=bytearray(data[:token_offset]+struct.pack('>I',4)+data[token_offset:])
                fields[1]+=4
                for index in (2,3,4):
                    if fields[index] > token_offset:fields[index]+=4
                fields[9]+=4
                struct.pack_into('>10I',result,0,*fields)
                return bytes(result),True
            offset=(offset+length+3)&~3
        elif token == 4:
            continue
        elif token == 9:
            break
        else:raise ValueError('Invalid FDT token')
    raise ValueError('Missing secure-chosen kaslr-seed')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dtbs',nargs='+',type=Path)
    args=parser.parse_args()
    for path in args.dtbs:
        result,changed=align_seed(path.read_bytes())
        if changed:path.write_bytes(result)
