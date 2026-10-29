"""Prints the Luau 'Layouts' table for HairConfig from riginfo.json."""
import json, sys
info = json.load(open(sys.argv[1]))
def v3(p): return 'Vector3.new(%s, %s, %s)' % tuple(('%.4f' % c).rstrip('0').rstrip('.') if c else '0' for c in p)
out = ['HairConfig.Layouts = {']
for h in info:
    out.append('\t%s = {' % h['name'])
    out.append('\t\tSize = %s, -- size of the whole hair mesh in studs (used to check the import scale)' % v3(h['size']))
    out.append('\t\tChains = {')
    for c in h['chains']:
        bones = ', '.join('"%s"' % b for b in c['bones'][:-1])
        radii = ', '.join('%g' % r for r in c['radii'])
        out.append('\t\t\t{ Name = "%s", Bones = { %s }, Tip = "%s", Radii = { %s } },' % (c['name'], bones, c['bones'][-1], radii))
    out.append('\t\t},')
    out.append('\t\t-- where every bone sits relative to the centre of the head, as modeled')
    out.append('\t\tBones = {')
    for name, p in h['bones'].items():
        out.append('\t\t\t%s = %s,' % (name, v3(p)))
    out.append('\t\t},')
    out.append('\t},')
out.append('}')
print('\n'.join(out))
