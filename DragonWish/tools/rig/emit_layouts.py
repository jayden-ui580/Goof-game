"""Prints the Luau Layouts table for HairConfig from riginfo.json."""
import json, sys
info = json.load(open(sys.argv[1]))
def num(c): return ('%.4f' % c).rstrip('0').rstrip('.') if abs(c) > 1e-9 else '0'
def v3(p): return 'Vector3.new(%s, %s, %s)' % tuple(num(c) for c in p)
out = ['HairConfig.Layouts = {']
for h in info:
    out.append('\t%s = {' % h['name'])
    out.append('\t\tAttach = "%s", -- the body part it is fixed to' % h['attach'])
    out.append('\t\tSize = %s,' % v3(h['size']))
    out.append('\t\tHeadCenter = Vector3.zero, -- the rig point that sits on the centre of that body part')
    out.append('\t\tChains = {')
    for c in h['chains']:
        bones = ', '.join('"%s"' % b for b in c['bones'][:-1])
        radii = ', '.join('%g' % r for r in c['radii'])
        out.append('\t\t\t{ Name = "%s", Bones = { %s }, Tip = "%s", Radii = { %s } },' % (c['name'], bones, c['bones'][-1], radii))
    out.append('\t\t},')
    out.append('\t\tBones = {')
    for name, p in h['bones'].items():
        out.append('\t\t\t%s = %s,' % (name, v3(p)))
    out.append('\t\t},')
    out.append('\t},')
out.append('}')
print('\n'.join(out))
