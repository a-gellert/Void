embedded_components {
  id: "mesh"
  type: "model"
  data: "mesh: \"/assets/models/beacon.gltf\"\nname: \"beacon\"\nmaterials {\n  name: \"default\"\n  material: \"/assets/materials/space_emissive.material\"\n  textures {\n    sampler: \"tex0\"\n    texture: \"/assets/textures/palette_256.png\"\n  }\n}\n"
}
embedded_components {
  id: "zone"
  type: "model"
  data: "mesh: \"/assets/models/vfx_sphere.gltf\"\nname: \"zone\"\nmaterials {\n  name: \"default\"\n  material: \"/assets/materials/space_emissive.material\"\n  textures {\n    sampler: \"tex0\"\n    texture: \"/assets/textures/palette_256.png\"\n  }\n}\n"
  scale {
    x: 20.0
    y: 20.0
    z: 20.0
  }
}
