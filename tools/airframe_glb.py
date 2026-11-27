"""Shared offline GLB reader, writer and buffer compaction for the aircraft tools."""

from struct import pack, unpack_from

from bake_j20_breakup import read_model


class AirframeGLB:
    def __init__(self, source):
        self.doc, self.buffer = read_model(source)
        self.access = self.doc["accessors"]
        self.views = self.doc["bufferViews"]
        self.nodes = self.doc["nodes"]
        self.meshes = self.doc["meshes"]
        self.materials = self.doc["materials"]
        self.scene = self.doc["scenes"][self.doc["scene"]]["nodes"]
        self.names = {entry["name"]: i for i, entry in enumerate(self.materials)}

    def read(self, index):
        a = self.access[index]
        view = self.views[a["bufferView"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        schema = {5123: "H", 5125: "I", 5126: "f"}[a["componentType"]]
        stride = view.get("byteStride", width * (2 if schema == "H" else 4))
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        return [unpack_from("<" + schema * width, self.buffer, start + i * stride) for i in range(a["count"])]

    def append(self, rows, kind):
        start = len(self.buffer)
        scalar = kind == "SCALAR"
        schema = "H" if scalar and max(v[0] for v in rows) < 65536 else "I" if scalar else "f"
        for row in rows:
            self.buffer.extend(pack("<" + schema * len(row), *row))
        end = len(self.buffer)
        self.buffer.extend(b"\0" * (-end % 4))
        self.views.append({"buffer": 0, "byteOffset": start, "byteLength": end - start})
        a = {"bufferView": len(self.views) - 1, "componentType": {"H": 5123, "I": 5125, "f": 5126}[schema],
             "count": len(rows), "type": kind}
        if kind == "VEC3":
            a.update(min=list(map(min, zip(*rows))), max=list(map(max, zip(*rows))))
        self.access.append(a)
        return len(self.access) - 1

    def compact(self):
        # Drop superseded accessor payloads, including the previous breakup,
        # without re-encoding any preserved textures or animation channels.
        used_meshes = sorted({n["mesh"] for n in self.nodes if "mesh" in n})
        mesh_map = {old: i for i, old in enumerate(used_meshes)}
        self.doc["meshes"] = [self.meshes[i] for i in used_meshes]
        for n in self.nodes:
            if "mesh" in n:
                n["mesh"] = mesh_map[n["mesh"]]
        bindings = []
        for mesh in self.doc["meshes"]:
            for p in mesh["primitives"]:
                bindings.extend((p["attributes"], key) for key in p["attributes"])
                if "indices" in p:
                    bindings.append((p, "indices"))
        for clip in self.doc.get("animations", []):
            for sampler in clip["samplers"]:
                bindings.extend(((sampler, "input"), (sampler, "output")))
        accessors = sorted({section[key] for section, key in bindings})
        mapping = {ix: i for i, ix in enumerate(accessors)}
        for section, key in bindings:
            section[key] = mapping[section[key]]
        self.doc["accessors"] = [self.access[ix] for ix in accessors]
        bound_views = self.doc["accessors"] + [im for im in self.doc.get("images", []) if "bufferView" in im]
        views = sorted({view["bufferView"] for view in bound_views})
        mapping = {ix: i for i, ix in enumerate(views)}
        for view in bound_views:
            view["bufferView"] = mapping[view["bufferView"]]
        compact = bytearray()
        self.doc["bufferViews"] = []
        for ix in views:
            view = self.views[ix]
            start = view.get("byteOffset", 0)
            compact.extend(b"\0" * (-len(compact) % 4))
            self.doc["bufferViews"].append({**view, "byteOffset": len(compact)})
            compact.extend(self.buffer[start:start + view["byteLength"]])
        compact.extend(b"\0" * (-len(compact) % 4))
        return compact
