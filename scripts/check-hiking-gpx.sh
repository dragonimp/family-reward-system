set -euo pipefail
python3 - <<'PY'
import os
from pathlib import Path
s=Path('parent-app/ios/HappyLifeParent/ExerciseView.swift').read_text();s=s[s.index('private final class HikingGPXReader:'):]
s='import Foundation\nimport CoreLocation\n'+s+'''
private func readGPX(_ xml: String) -> HikingGPXReader {
 let reader = HikingGPXReader(); let parser = XMLParser(data: Data(xml.utf8)); parser.shouldResolveExternalEntities = false; parser.delegate = reader; _ = parser.parse(); return reader
}
private let valid = readGPX("<gpx><trk><trkseg><trkpt lat='30' lon='120'><ele>80</ele></trkpt><trkpt lat='30.01' lon='120.01'><ele>120</ele></trkpt></trkseg><trkseg><trkpt lat='31' lon='121'/></trkseg></trk></gpx>")
assert(valid.segments.count == 2 && valid.segments[0].count == 2 && valid.highest == 120)
assert(readGPX("<gpx><rte><rtept lat='91' lon='120'/></rte></gpx>").failed)
assert(readGPX("<gpx><rte><rtept lat='nan' lon='120'/></rte></gpx>").failed)
let excessive = "<gpx><rte>" + String(repeating: "<rtept lat='30' lon='120'/>", count: 20001) + "</rte></gpx>"
assert(readGPX(excessive).failed)
print("PASS: GPX segments, elevation, bounds, non-finite input and point cap")
'''
Path(os.environ['ATLAS_BUILD_WORK'],'gpx-check.swift').write_text(s)
PY
xcrun swiftc "$ATLAS_BUILD_WORK/gpx-check.swift" -o "$ATLAS_BUILD_WORK/gpx-check"
"$ATLAS_BUILD_WORK/gpx-check" > "$ATLAS_BUILD_OUTPUT/checks.txt"
xcrun swiftc -frontend -parse parent-app/ios/HappyLifeParent/ExerciseView.swift
