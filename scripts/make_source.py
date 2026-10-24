"""Gera o source.json que o SideStore/AltStore usam para instalar e atualizar o ScanFusion."""
import json, os, sys, datetime

repo, version, build, ipa = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
owner = repo.split("/")[0]
base = f"https://github.com/{repo}/releases/download/latest"
source = {
    "name": "ScanFusion",
    "subtitle": "Scanner 3D com LiDAR para o Fusion",
    "identifier": f"io.github.{owner.lower()}.scanfusion.source",
    "sourceURL": f"{base}/source.json",
    "iconURL": f"https://raw.githubusercontent.com/{repo}/main/docs/icon.png",
    "tintColor": "C9A24A",
    "apps": [{
        "name": "ScanFusion",
        "bundleIdentifier": "com.scanfusion.app",
        "developerName": owner,
        "subtitle": "Objeto, ambiente, malha, nuvem de pontos e trena.",
        "localizedDescription": "Escaneie com o LiDAR do iPhone e exporte STL, OBJ, PLY, PTS e DXF para Fusion, Revit e AutoCAD.",
        "iconURL": f"https://raw.githubusercontent.com/{repo}/main/docs/icon.png",
        "tintColor": "C9A24A",
        "category": "utilities",
        "versions": [{
            "version": version,
            "buildVersion": build,
            "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "downloadURL": f"{base}/ScanFusion.ipa",
            "size": os.path.getsize(ipa),
            "minOSVersion": "17.0",
            "localizedDescription": f"Build {build}"
        }],
        "appPermissions": {"entitlements": [], "privacy": {
            "NSCameraUsageDescription": "Usar a câmera e o LiDAR para escanear objetos e ambientes em 3D."
        }}
    }],
    "news": []
}
with open("source.json", "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
print(json.dumps(source, ensure_ascii=False, indent=2))
