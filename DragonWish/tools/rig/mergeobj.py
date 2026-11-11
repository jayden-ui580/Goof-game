"""Joins OBJ files into one (v / vt / vn / f, with each file's indices shifted): SSJ3 came as a front and
a back piece; the game needs one mesh with one skeleton.
usage: python mergeobj.py <out.obj> <in1.obj> <in2.obj> ..."""
import sys
out = open(sys.argv[1], 'w')
out.write('# merged\ng Handle1\n')
ov = ot = on = 0
for path in sys.argv[2:]:
    nv = nt = nn = 0
    for line in open(path):
        p = line.split()
        if not p: continue
        if p[0] == 'v': out.write(line); nv += 1
        elif p[0] == 'vt': out.write(line); nt += 1
        elif p[0] == 'vn': out.write(line); nn += 1
        elif p[0] == 'f':
            idx = []
            for t in p[1:]:
                a = (t.split('/') + ['', ''])[:3]
                idx.append('/'.join(str(int(x) + o) if x else '' for x, o in zip(a, (ov, ot, on))))
            out.write('f ' + ' '.join(idx) + '\n')
    ov += nv; ot += nt; on += nn
out.close()
