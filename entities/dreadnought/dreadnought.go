embedded_components {
  id: "hull"
  type: "model"
  data: "mesh: \"/assets/models/dreadnought_hull.gltf\"\nname: \"hull\"\nmaterials {\n  name: \"default\"\n  material: \"/assets/materials/space_palette.material\"\n  textures {\n    sampler: \"tex0\"\n    texture: \"/assets/textures/palette_256.png\"\n  }\n}\n"
}
embedded_components {
  id: "gen"
  type: "model"
  data: "mesh: \"/assets/models/dreadnought_gen.gltf\"\nname: \"gen\"\nmaterials {\n  name: \"default\"\n  material: \"/assets/materials/space_palette.material\"\n  textures {\n    sampler: \"tex0\"\n    texture: \"/assets/textures/palette_256.png\"\n  }\n}\n"
}
embedded_components {
  id: "turret"
  type: "model"
  data: "mesh: \"/assets/models/dreadnought_turret.gltf\"\nname: \"turret\"\nmaterials {\n  name: \"default\"\n  material: \"/assets/materials/space_palette.material\"\n  textures {\n    sampler: \"tex0\"\n    texture: \"/assets/textures/palette_256.png\"\n  }\n}\n"
}
embedded_components {
  id: "reactor"
  type: "model"
  data: "mesh: \"/assets/models/dreadnought_reactor.gltf\"\nname: \"reactor\"\nmaterials {\n  name: \"default\"\n  material: \"/assets/materials/space_emissive.material\"\n  textures {\n    sampler: \"tex0\"\n    texture: \"/assets/textures/palette_256.png\"\n  }\n}\n"
}
embedded_components {
  id: "dome"
  type: "model"
  data: "mesh: \"/assets/models/vfx_sphere.gltf\"\nname: \"dome\"\nmaterials {\n  name: \"default\"\n  material: \"/assets/materials/space_emissive.material\"\n  textures {\n    sampler: \"tex0\"\n    texture: \"/assets/textures/palette_256.png\"\n  }\n}\n"
  position {
    x: 0.0
    y: 2.0
    z: 0.0
  }
  scale {
    x: 42.0
    y: 28.0
    z: 76.0
  }
}
