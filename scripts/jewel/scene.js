import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

const Q = new URLSearchParams(location.search);
const W = +(Q.get('w') || 1600), H = +(Q.get('h') || 900);
const SHOT = Q.get('shot') || 'hero';       // hero | board | sprites | lineup
const THEME = Q.get('theme') || 'faberge';  // faberge | malachite
const P = (k, d) => (Q.has(k) ? +Q.get(k) : d);

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(W, H);
renderer.toneMapping = Q.get('tm')==='agx' ? THREE.AgXToneMapping : THREE.NeutralToneMapping;
renderer.toneMappingExposure = P('exp', 1.0);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
document.body.appendChild(renderer.domElement);
const scene = new THREE.Scene();

// ---------------------------------------------------------------- environment
// side 'w' or 'b' only matters for sprites: the dark side gets strip lights behind the piece, so its
// polished outline catches a bright edge on dark squares; the light side keeps the back dark, so its
// outline reflects shadow and holds a contour on light squares.
function makeEnv(side, card = true) {
  const es = new THREE.Scene();
  const T = THEMES[THEME].env;
  es.add(new THREE.Mesh(new THREE.SphereGeometry(50, 32, 16), new THREE.MeshBasicMaterial({ color: new THREE.Color(T.room), side: THREE.BackSide })));
  const panel = (w, h, col, k, pos, rot) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(col).multiplyScalar(k), side: THREE.DoubleSide }));
    m.position.set(...pos); m.rotation.set(...rot); es.add(m);
  };
  const sprite = SHOT === 'sprites';
  if (SHOT !== 'board') panel(14, 8, 0xffffff, 3.0, [-3, 12, -2], [Math.PI / 2, 0, 0.5]);      // big top softbox
  else panel(30, 30, 0xffffff, 0.06, [0, 14, 0], [Math.PI / 2, 0, 0]);
  panel(3, 16, T.warm, 4.0, [-14, 5, 2], [0, Math.PI / 2, 0]);           // warm strip left
  panel(3, 16, T.cool, sprite ? P('cs', TH.fill ?? 2.0) : 2.6, [14, 5, -2], [0, -Math.PI / 2, 0]);          // cool strip right (dimmer for sprites: the right side in soft shade, never black)
  // a warm reflector card in front of and below the piece, as in a studio: the upright faces of gold
  // reflect it instead of the dark floor
  if (sprite && card) panel(26, 9, T.warm, P('fr', TH.reflector ?? 1.2), [0, -6, 13], [0, 0, 0]);
  if (sprite && side === 'b') {
    const k = P('rb', TH.rimEnv ?? 3);
    panel(26, 8, 0xffffff, k, [0, -6.5, -13], [0, 0, 0]);                // a wide light behind and below the piece
    panel(2.6, 18, T.cool, k * 1.6, [-8, -1, -11], [0, 0.6, 0]);          // strip behind left
    panel(2.6, 18, T.warm, k * 1.6, [8, -1, -11], [0, -0.6, 0]);          // strip behind right
  }
  panel(18, 2, 0xffffff, 2.0, [0, 3, -16], [0, 0, 0]);                   // back rim
  if (SHOT !== 'board') panel(22, 9, 0xfff4e6, P('bs', 2.4), [0, 11, -14], [-0.66, 0, 0]);   // big back softbox, reflected by upward faces
  if (SHOT !== 'board') panel(8, 8, 0xffffff, 1.4, [-10, 5, 9], [0, -0.85, 0]);   // left-front softbox for side faces
  // soft horizon band so polished metal always has something warm to reflect
  const band = new THREE.Mesh(new THREE.CylinderGeometry(30, 30, 10, 64, 1, true), new THREE.MeshBasicMaterial({ color: new THREE.Color(T.warm).multiplyScalar(P('hz', 0.55)), side: THREE.BackSide }));
  band.position.y = 3; if (SHOT !== 'board') es.add(band);
  panel(12, 1.5, T.warm, P('fk', 1.4), [0, 1.5, 16], [0, Math.PI, 0]);            // front kicker
  if (SHOT !== 'board') panel(6, 6, 0xffffff, 1.2, [6, 10, 8], [Math.PI / 2, 0, 0]);
  const pm = new THREE.PMREMGenerator(renderer);
  return pm.fromScene(es, 0.02).texture;
}

// ---------------------------------------------------------------- themes
const C = (r, g, b) => new THREE.Color(r, g, b);
// On the boards whose middle squares glow as bright as the light pieces, those pieces get a fine
// contour shade (see contour(): 4.5 px of the sprite, about 0.55 pt on the phone at k = 1.2).
const GLOW_CONTOUR = { w: [4.5, 0.4, 1.5] };
const THEMES = {
  faberge: {
    env: { room: 0x23201c, warm: 0xffd9a0, cool: 0xa9c4ff },
    // board shader colors
    enamelDeep: C(0.008, 0.022, 0.17), enamelHi: C(0.07, 0.22, 0.88),
    pearl: C(0.95, 0.93, 0.89), metal: C(1.0, 0.77, 0.36), metalRough: 0.2, border: 'enamel',
    beads: true, frame: 'metal',
    mats: () => {
      const gold = new THREE.MeshPhysicalMaterial({ color: C(1.0, 0.78, 0.36), metalness: 1, roughness: 0.2, envMapIntensity: P("gi", 2.2) });
      const pearl = new THREE.MeshPhysicalMaterial({ color: C(0.96, 0.94, 0.9), roughness: 0.18, clearcoat: 1, clearcoatRoughness: 0.04, sheen: 0.4, sheenColor: C(1, 0.9, 0.95), iridescence: 0.35, iridescenceIOR: 1.4 });
      const midnight = new THREE.MeshPhysicalMaterial({ color: C(0.012, 0.025, 0.11), roughness: 0.32, metalness: 0.15, clearcoat: 1, clearcoatRoughness: 0.03 });
      const sapphire = new THREE.MeshPhysicalMaterial({ color: C(0.05, 0.18, 0.95), roughness: 0.02, metalness: 0.2, clearcoat: 1, clearcoatRoughness: 0.0, envMapIntensity: 2.2 });
      const diamond = new THREE.MeshPhysicalMaterial({ color: C(0.95, 0.97, 1.0), roughness: 0.0, metalness: 1, envMapIntensity: 2.6 });
      // gold pieces: the shapes that mark them in gold, set with sapphire; midnight pieces: gold
      return { w: { body: gold, trim: pearl, accent: gold, gem: sapphire, cap: sapphire, lining: sapphire, eye: sapphire, mane: sapphire },
               b: { body: midnight, trim: gold, gem: diamond, eye: gold } };
    },
  },
  blueprint: {
    env: { room: 0x1a2230, warm: 0xfff1dc, cool: 0xbcd6ff },
    cA: C(0.063, 0.145, 0.267), cB: C(0.118, 0.259, 0.459), cC: C(0.118, 0.259, 0.459),
    pearl: C(0.9, 0.93, 0.97), metal: C(1.0, 0.78, 0.34), metalRough: 0.3, border: 'ink',
    beads: false, frame: 'navy', wire: true,
    mats: () => {
      const plaster = new THREE.MeshPhysicalMaterial({ color: C(0.9, 0.925, 0.96), roughness: 0.42, clearcoat: 0.5, clearcoatRoughness: 0.18, envMapIntensity: P('pe', 0.75) });
      const inkGlass = new THREE.MeshPhysicalMaterial({ color: C(0.025, 0.05, 0.11), roughness: 0.22, clearcoat: 1, clearcoatRoughness: 0.03 });
      const amber = new THREE.MeshPhysicalMaterial({ color: C(1.0, 0.74, 0.3), metalness: 1, roughness: 0.28, envMapIntensity: 1.6 });
      const navyInk = new THREE.MeshBasicMaterial({ color: new THREE.Color(P('wi', 0x17335c)) });
      const paleInk = new THREE.MeshBasicMaterial({ color: new THREE.Color(0xd6e6ff) });
      const socketW = new THREE.MeshPhysicalMaterial({ color: C(0.02, 0.05, 0.12), roughness: 0.15, clearcoat: 1 });
      const socketB = new THREE.MeshPhysicalMaterial({ color: C(0.75, 0.85, 1.0), roughness: 0.2, clearcoat: 1 });
      return { w: { body: plaster, trim: amber, gem: amber, eye: amber, ink: navyInk, socket: socketW },
               b: { body: inkGlass, trim: amber, gem: amber, eye: amber, ink: paleInk, socket: socketB } };
    },
  },

  spark: {
    rival: 0, env: { room: 0x1a1410, warm: 0xffc070, cool: 0xffd9a8 },
    cA: C(0.09, 0.05, 0.03), cB: C(0.72, 0.42, 0.15), cC: C(0.04, 0.022, 0.012), cD: C(1.0, 0.5, 0.12),
    pearl: C(1, 0.9, 0.7), metal: C(1.0, 0.74, 0.28), metalRough: 0.2, frame: 'night', motif: 0.9, contour: GLOW_CONTOUR,
    mats: () => {
      // paler than the board's amber squares, so the pieces stand apart from them
      const ember = new THREE.MeshPhysicalMaterial({ color: C(1.0, 0.9, 0.72), roughness: 0.16, clearcoat: 1, clearcoatRoughness: 0.03, emissive: C(0.2, 0.08, 0.0), sheen: 0.4, sheenColor: C(1, 0.85, 0.55) });
      const obsidian = new THREE.MeshPhysicalMaterial({ color: C(0.025, 0.018, 0.014), roughness: 0.1, clearcoat: 1, clearcoatRoughness: 0.02 });
      const gold = new THREE.MeshPhysicalMaterial({ color: C(1.0, 0.76, 0.32), metalness: 1, roughness: 0.18, envMapIntensity: 2.0 });
      const glow = new THREE.MeshBasicMaterial({ color: C(1.0, 0.6, 0.15) });
      return { w: { body: ember, trim: gold, gem: glow, eye: gold }, b: { body: obsidian, trim: gold, gem: glow, eye: gold } };
    },
  },
  drift: {
    rival: 1, env: { room: 0x101820, warm: 0xd8c0ff, cool: 0x9ffff0 },
    cA: C(0.03, 0.085, 0.12), cB: C(0.33, 0.66, 0.66), cC: C(0.015, 0.04, 0.06), cD: C(1.0, 0.55, 0.85),
    pearl: C(0.8, 1, 0.97), metal: C(0.78, 0.58, 1.0), metalRough: 0.2, frame: 'night', motif: 1.0, contour: GLOW_CONTOUR,
    mats: () => {
      const aqua = new THREE.MeshPhysicalMaterial({ color: C(0.62, 0.98, 0.93), roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.02, iridescence: 0.6, iridescenceIOR: 1.4, emissive: C(0.02, 0.12, 0.11) });
      const indigo = new THREE.MeshPhysicalMaterial({ color: C(0.03, 0.035, 0.11), roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.02, iridescence: 0.4 });
      const orbit = new THREE.MeshPhysicalMaterial({ color: C(0.92, 0.62, 1.0), metalness: 1, roughness: 0.2, envMapIntensity: 1.8 });
      const glow = new THREE.MeshBasicMaterial({ color: C(1.0, 0.6, 0.95) });
      return { w: { body: aqua, trim: orbit, gem: glow, eye: orbit }, b: { body: indigo, trim: orbit, gem: glow, eye: orbit } };
    },
  },
  pulse: {
    rival: 2, env: { room: 0x0c1420, warm: 0xc8f4ff, cool: 0x7fe6ff },
    cA: C(0.02, 0.05, 0.11), cB: C(0.17, 0.43, 0.64), cC: C(0.01, 0.025, 0.06), cD: C(0.75, 1.0, 1.0),
    pearl: C(0.85, 0.97, 1), metal: C(0.3, 0.88, 1.0), metalRough: 0.2, frame: 'night', motif: 0.9, contour: GLOW_CONTOUR,
    mats: () => {
      const ice = new THREE.MeshPhysicalMaterial({ color: C(0.86, 0.97, 1.0), roughness: 0.14, clearcoat: 1, clearcoatRoughness: 0.02, sheen: 0.6, sheenColor: C(0.5, 0.95, 1.0) });
      const night = new THREE.MeshPhysicalMaterial({ color: C(0.012, 0.03, 0.075), roughness: 0.1, clearcoat: 1, clearcoatRoughness: 0.02 });
      const cyan = new THREE.MeshPhysicalMaterial({ color: C(0.35, 0.9, 1.0), metalness: 0.6, roughness: 0.15, emissive: C(0.05, 0.35, 0.45) });
      const glow = new THREE.MeshBasicMaterial({ color: C(0.55, 0.95, 1.0) });
      return { w: { body: ice, trim: cyan, gem: glow, eye: cyan }, b: { body: night, trim: cyan, gem: glow, eye: cyan } };
    },
  },
  vector: {
    rival: 3, env: { room: 0x140c20, warm: 0xe0c8ff, cool: 0xc890ff }, facets: 12,
    cA: C(0.085, 0.035, 0.17), cB: C(0.45, 0.29, 0.75), cC: C(0.04, 0.015, 0.09), cD: C(0.95, 0.45, 1.0),
    pearl: C(0.9, 0.85, 1), metal: C(0.8, 0.62, 1.0), metalRough: 0.2, frame: 'night', motif: 1.0,
    mats: () => {
      const crystal = new THREE.MeshPhysicalMaterial({ color: C(0.84, 0.76, 1.0), roughness: 0.06, clearcoat: 1, clearcoatRoughness: 0.0, iridescence: 0.8, iridescenceIOR: 1.6, flatShading: true, envMapIntensity: 1.6 });
      const deep = new THREE.MeshPhysicalMaterial({ color: C(0.07, 0.025, 0.16), roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.0, flatShading: true, iridescence: 0.5, envMapIntensity: 1.6 });
      const lilac = new THREE.MeshPhysicalMaterial({ color: C(0.86, 0.7, 1.0), metalness: 1, roughness: 0.16, envMapIntensity: 1.8 });
      const glow = new THREE.MeshBasicMaterial({ color: C(0.95, 0.55, 1.0) });
      return { w: { body: crystal, trim: lilac, gem: glow, eye: lilac }, b: { body: deep, trim: lilac, gem: glow, eye: lilac } };
    },
  },
  singularity: {
    rival: 4, env: { room: 0x100c14, warm: 0xffd6f4, cool: 0xd8d0ff },
    cA: C(0.03, 0.022, 0.045), cB: C(0.33, 0.30, 0.42), cC: C(0.012, 0.01, 0.018), cD: C(1.0, 0.35, 0.85),
    pearl: C(0.95, 0.95, 1), metal: C(0.92, 0.9, 1.0), metalRough: 0.2, frame: 'night', motif: 1.0,
    mats: () => {
      const pearl = new THREE.MeshPhysicalMaterial({ color: C(0.95, 0.95, 0.98), roughness: 0.16, clearcoat: 1, clearcoatRoughness: 0.03, iridescence: 0.7, iridescenceIOR: 1.45, iridescenceThicknessRange: [300, 800] });
      const voidm = new THREE.MeshPhysicalMaterial({ color: C(0.006, 0.005, 0.01), roughness: 0.06, clearcoat: 1, clearcoatRoughness: 0.0 });
      const magenta = new THREE.MeshPhysicalMaterial({ color: C(1.0, 0.45, 0.88), metalness: 1, roughness: 0.18, envMapIntensity: 1.8 });
      const glow = new THREE.MeshBasicMaterial({ color: C(1.0, 0.85, 1.0) });
      return { w: { body: pearl, trim: magenta, gem: glow, eye: magenta }, b: { body: voidm, trim: magenta, gem: glow, eye: magenta } };
    },
  },
  malachite: {
    env: { room: 0x1e1d1b, warm: 0xffd2b8, cool: 0xc8ffe8 },
    stoneDark: C(0.02, 0.20, 0.11), stoneMid: C(0.05, 0.45, 0.25), stoneHi: C(0.26, 0.70, 0.46),
    pearl: C(0.95, 0.94, 0.92), metal: C(0.97, 0.66, 0.55), metalRough: 0.22, border: 'onyx',
    beads: false, frame: 'onyx',
    mats: () => {
      const rose = new THREE.MeshPhysicalMaterial({ color: C(0.98, 0.67, 0.56), metalness: 1, roughness: 0.2, envMapIntensity: 1.2 });
      const nacre = new THREE.MeshPhysicalMaterial({ color: C(0.94, 0.94, 0.93), roughness: 0.2, clearcoat: 1, clearcoatRoughness: 0.05, iridescence: 1.0, iridescenceIOR: 1.5, iridescenceThicknessRange: [300, 900], sheen: 0.6, sheenColor: C(0.9, 1.0, 0.98) });
      const onyx = new THREE.MeshPhysicalMaterial({ color: C(0.010, 0.012, 0.012), roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.02 });
      const emerald = new THREE.MeshPhysicalMaterial({ color: C(0.02, 0.6, 0.3), roughness: 0.0, metalness: 0.3, clearcoat: 1, envMapIntensity: 2.0 });
      return { w: { body: nacre, trim: rose, gem: rose, eye: rose }, b: { body: onyx, trim: rose, gem: emerald, eye: rose } };
    },
  },
};
const TH = THEMES[THEME];
scene.environment = makeEnv();
scene.environmentIntensity = P('env', 1.0);

// ---------------------------------------------------------------- procedural board texture
const glslCommon = /* glsl */`
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p){ vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.0-2.0*f);
  return mix(mix(hash(i),hash(i+vec2(1,0)),u.x), mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x), u.y); }
float fbm(vec2 p){ float v=0.0, a=0.5; for(int i=0;i<6;i++){ v+=a*noise(p); p=p*2.03+vec2(1.7,9.2); a*=0.5; } return v; }
vec2 rot(vec2 p, float a){ float c=cos(a), s=sin(a); return vec2(c*p.x-s*p.y, s*p.x+c*p.y); }
`;
const BOARD_FRAG = /* glsl */`
precision highp float;
varying vec2 vUv;
uniform int uMode;            // 0 albedo, 1 (height, roughness, metal), 2 iridescence mask
uniform int uTheme;           // 0 faberge, 1 malachite
uniform sampler2D uLabels;
uniform vec3 cA, cB, cC, cPearl, cMetal, cD;
uniform int uRival;
uniform float uMotif;
uniform float uMetalRough;
uniform float uBumpK;
${glslCommon}
const float BORDER = 0.5;
void main(){
  vec2 B = vUv * (8.0 + 2.0*BORDER) - BORDER;          // board coords, squares 0..8
  vec2 cell = floor(B); vec2 f = fract(B); vec2 p = f - 0.5;
  bool inside = B.x >= 0.0 && B.x <= 8.0 && B.y >= 0.0 && B.y <= 8.0;
  bool dark = mod(cell.x + cell.y, 2.0) < 0.5;
  float s = hash(cell + 3.1);
  vec3 col; float height = 0.0, rough = 0.06, metal = 0.0, irid = 0.0;
  float lineW = uTheme == 0 ? 0.014 : 0.008;


  if (uTheme == 3) {
    vec2 c = B - 4.0; float r = length(c); float th = atan(c.y, c.x);
    float n = fbm(B * 1.6 + 3.0), n2 = fbm(B * 6.0 + 9.0);
    if (inside) {
      if (dark) col = cA * (0.78 + 0.45 * n);
      else {
        float q = 1.0 - smoothstep(0.0, 0.8, length(p));
        col = cB * (0.86 + 0.16 * n + 0.04 * n2) * (0.93 + 0.12 * q);
      }
    } else {
      col = cC * (0.65 + 0.6 * n);
    }
    // the rival's motif, drawn as light over the glass
    vec3 add = vec3(0.0);
    if (uRival == 0) {
      // Spark: a sphere of golden sparkles, dense at the center, embers drifting outward
      float core = exp(-r * r / 7.0);
      for (int L = 0; L < 3; L++) {
        float k = 4.0 + float(L) * 5.0;
        vec2 uv = B * k + float(L) * 17.0; vec2 g = floor(uv), fr = fract(uv) - 0.5;
        float h = hash(g + float(L));
        float keep = 0.25 + 0.55 * core;
        if (h < keep) { vec2 o = (vec2(hash(g + 1.3), hash(g + 7.1)) - 0.5) * 0.8; vec2 dv = fr - o;
          float d = length(dv);
          float sz = 0.05 + 0.08 * hash(g + 3.3) * (0.4 + core);
          float b = (1.0 - smoothstep(0.0, sz, d)) * (0.4 + 0.6 * hash(g + 5.5));
          // a four-point twinkle on the bigger ones
          float star = max(0.0, 1.0 - abs(dv.x) * 9.0) * max(0.0, 1.0 - abs(dv.y) * 40.0) + max(0.0, 1.0 - abs(dv.y) * 9.0) * max(0.0, 1.0 - abs(dv.x) * 40.0);
          b += star * 0.5 * step(0.7, hash(g + 3.3));
          add += mix(cMetal, vec3(1.0, 0.95, 0.75), hash(g + 9.9) * core) * b * (1.4 - 0.3 * float(L)); }
      }
      add += mix(cD, cMetal, 0.5) * core * 0.55;
      add += vec3(1.0, 0.6, 0.2) * exp(-r * r / 1.2) * 0.35;
    } else if (uRival == 1) {
      // Drift: a soft aqua orb under the glass and one broad, tilted wash of lavender light (no edges)
      vec2 q = rot(c, -0.38);
      float band = exp(-pow(q.y / 1.7, 2.0));
      vec3 rc = mix(cMetal, cD, 0.5 + 0.5 * sin(q.x * 0.55));
      add += rc * band * 0.3;
      add += vec3(0.45, 1.0, 0.92) * exp(-r * r / 3.2) * 0.3;
      add += vec3(1.0) * pow(max(0.0, hash(floor(B * 14.0)) - 0.94) * 16.0, 2.0) * (1.0 - smoothstep(0.0, 0.08, length(fract(B * 14.0) - 0.5))) * 0.5;
    } else if (uRival == 2) {
      // Pulse: one soft cyan glow from the center, like a light under the glass
      add += cD * exp(-r * r / 2.4) * 0.5;
      add += cMetal * exp(-r * r / 9.0) * 0.2;
      add += vec3(1.0) * pow(max(0.0, hash(floor(B * 16.0)) - 0.95) * 20.0, 2.0) * (1.0 - smoothstep(0.0, 0.07, length(fract(B * 16.0) - 0.5))) * 0.5;
    } else if (uRival == 3) {
      // Vector: each square a softly bevelled crystal tile, lit from its own direction (no lines)
      if (inside) {
        float a = hash(cell * 1.7 + 2.2) * 6.2832;
        vec2 dir = vec2(cos(a), sin(a));
        float bevel = 0.5 + 0.5 * clamp(dot(p, dir) * 1.4, -1.0, 1.0);
        col *= 0.84 + 0.3 * bevel;
        add += cD * (0.5 + 0.5 * sin(hash(cell + 4.4) * 6.28)) * 0.05;
      }
      add += cD * exp(-r * r / 6.0) * 0.16;
    } else {
      // Singularity: a soft dark well at the center with magenta and blue light bending around it (no ring)
      float well = exp(-r * r / 2.6);
      col *= 1.0 - well * 0.7;
      vec2 m = c - vec2(1.7, -1.3), bl = c + vec2(1.7, 1.3);
      add += cD * exp(-dot(m, m) / 3.6) * 0.32;
      add += vec3(0.6, 0.75, 1.0) * exp(-dot(bl, bl) / 4.2) * 0.3;
      add += vec3(1.0) * pow(max(0.0, hash(floor(B * 18.0)) - 0.95) * 20.0, 2.0) * (1.0 - smoothstep(0.0, 0.07, length(fract(B * 18.0) - 0.5))) * 0.5;
    }
    col += add * uMotif * (inside ? (dark ? 1.0 : 0.6) : 1.2);
    // glowing seams between the squares, brighter where four squares meet
    if (inside) {
      float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
      float seam = 1.0 - smoothstep(0.0035, 0.009, d);
      col = mix(col, cMetal, seam * 0.85);
      col += cMetal * (1.0 - smoothstep(0.0, 0.05, d)) * 0.08;
      vec2 cn = abs(f - round(f));
      col += cMetal * (1.0 - smoothstep(0.0, 0.045, length(cn))) * 0.55;
    } else {
      float dIn = max(max(-B.x, B.x - 8.0), max(-B.y, B.y - 8.0));
      float rim = 1.0 - smoothstep(0.006, 0.014, abs(dIn - 0.015));
      float outer = 1.0 - smoothstep(0.005, 0.011, abs(dIn - (BORDER - 0.06)));
      col = mix(col, cMetal, max(rim, outer * 0.75));
      col += cMetal * (1.0 - smoothstep(0.0, 0.14, dIn)) * 0.12;
    }
    if (uMode == 1) { gl_FragColor = vec4(0.0, 0.12, 0.0, 1.0); return; }
    if (uMode == 2) { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }
    if (uMode == 3) {
      float dg = (vUv.x - vUv.y) * 0.7071;
      col += vec3(1.0) * (exp(-pow((dg + 0.18) / 0.22, 2.0)) * 0.05 + exp(-pow((dg + 0.48) / 0.06, 2.0)) * 0.025);
    }
    gl_FragColor = vec4(col, 1.0);
    return;
  }

  if (uTheme == 2) {
    // blueprint: drafting paper, white ink grid, dimension ticks and registration marks on the frame
    float paper = 0.96 + 0.08 * fbm(B * 7.0);
    vec3 ink = vec3(0.92, 0.95, 1.0);
    float a = 0.0;
    if (inside) {
      col = (dark ? cA : cB) * paper;
      vec2 g = abs(fract(B * 10.0 + 0.5) - 0.5) / 10.0;
      a = max(a, (1.0 - smoothstep(0.0012, 0.0026, min(g.x, g.y))) * (dark ? 0.08 : 0.11));
      float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
      a = max(a, (1.0 - smoothstep(0.0035, 0.0065, d)) * 0.7);
      vec2 pc = abs(p);
      float cross = (1.0 - smoothstep(0.0018, 0.0035, min(pc.x, pc.y))) * (1.0 - smoothstep(0.035, 0.04, max(pc.x, pc.y)));
      a = max(a, cross * 0.28);
    } else {
      float dIn = max(max(-B.x, B.x - 8.0), max(-B.y, B.y - 8.0));
      col = cA * 0.8 * paper;
      a = max(a, 1.0 - smoothstep(0.004, 0.008, abs(dIn - 0.008)));
      a = max(a, (1.0 - smoothstep(0.002, 0.004, abs(dIn - 0.40))) * 0.7);
      a = max(a, 1.0 - smoothstep(0.005, 0.009, abs(dIn - 0.445)));
      bool tb = B.y < 0.0 || B.y > 8.0;
      bool lr = B.x < 0.0 || B.x > 8.0;
      if (tb != lr) {
        float along = tb ? B.x : B.y;
        float t4 = abs(fract(along * 4.0 + 0.5) - 0.5) / 4.0;
        bool major = abs(fract(along + 0.5) - 0.5) < 0.02;
        float len = major ? 0.17 : 0.075;
        a = max(a, (1.0 - smoothstep(0.0025, 0.0045, t4)) * (1.0 - smoothstep(len, len + 0.006, dIn)) * 0.85);
      } else {
        vec2 cc = vec2(B.x < 0.0 ? -0.22 : 8.22, B.y < 0.0 ? -0.22 : 8.22);
        float rr = length(B - cc);
        a = max(a, (1.0 - smoothstep(0.003, 0.006, abs(rr - 0.1))) * 0.9);
        vec2 dc = abs(B - cc);
        a = max(a, (1.0 - smoothstep(0.002, 0.004, min(dc.x, dc.y))) * (1.0 - smoothstep(0.16, 0.166, max(dc.x, dc.y))) * 0.9);
      }
    }
    col = mix(col, ink, a);
    if (uMode == 1) gl_FragColor = vec4(a * 0.2, 0.5, 0.0, 1.0);
    else if (uMode == 2) gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    else gl_FragColor = vec4(col, 1.0);
    return;
  }

  if (inside) {
    if (uTheme == 0) {
      if (dark) {
        float r = length(p), th = atan(p.y, p.x);
        float g1 = sin(r * 6.2832 * 38.0 + 0.85 * sin(th * 12.0 + r * 14.0));
        float g2 = sin(th * 72.0 + r * 30.0) * 0.5 + 0.5;
        float h = 0.5 + 0.5 * g1;
        h = mix(h, h * (0.75 + 0.25 * g2), 0.35);
        float glowc = 1.0 - smoothstep(0.0, 0.62, r);
        col = mix(cA, cB, 0.18 + 0.55 * pow(h, 1.6) * (0.55 + 0.45 * glowc));
        col *= 0.85 + 0.3 * glowc;
      } else {
        // pearl enamel over a barleycorn guilloche
        vec2 q = rot(p, 0.785);
        float g = sin(q.x * 6.2832 * 34.0 + 0.8 * sin(q.y * 6.2832 * 6.0));
        float o = fbm(B * 2.3 + s * 10.0);
        col = cPearl * (0.97 + 0.025 * g);
        col = mix(col, col * vec3(1.02, 0.97, 1.0), smoothstep(0.4, 0.7, o) * 0.6);
        col = mix(col, col * vec3(0.97, 1.0, 1.03), smoothstep(0.55, 0.3, o) * 0.5);
      }
    } else {
      if (dark) {
        // malachite: each square cut from a different part of the stone
        vec2 q = rot(p, s * 6.2832);
        vec2 c1 = vec2(0.35 + 0.5 * s, -0.25 + 0.5 * hash(cell + 7.7));
        vec2 c2 = vec2(-0.45 - 0.3 * hash(cell + 2.2), 0.3 + 0.4 * hash(cell + 9.1));
        float wq = fbm(q * 1.6 + s * 31.0);
        float d1 = length(q - c1), d2 = length(q - c2) + 0.12;
        float k = 0.18; float h0 = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
        float d = mix(d2, d1, h0) - k * h0 * (1.0 - h0);          // smooth union of two 'eyes'
        d += 0.22 * wq + 0.035 * fbm(q * 7.0 + s * 3.0);
        float freq = 9.0;
        float bi = floor(d * freq), t = fract(d * freq);
        float hb = hash(vec2(bi, s * 17.0));
        float hb2 = hash(vec2(bi + 3.0, s * 5.0));
        vec3 band = hb < 0.33 ? cA : (hb < 0.75 ? cB : cC);
        band = mix(band, cB, 0.25 * hb2);
        // each band fades from a bright edge into a darker edge, with a crisp hairline between bands
        vec3 col0 = mix(band * 1.12, band * 0.62, smoothstep(0.0, 1.0, t));
        float sub = 0.5 + 0.5 * sin(t * 6.2832 * (3.0 + floor(hb2 * 4.0)));
        col0 *= 0.9 + 0.1 * sub;
        float hair = 1.0 - smoothstep(0.0, 0.06, t);
        col = mix(col0, cA * 0.35, hair * 0.8);
        col *= 0.96 + 0.08 * fbm(q * 40.0);
        rough = 0.05;
      } else {
        // mother of pearl: soft pastel flow with fine growth lines
        vec2 q = B * 1.3 + s * 11.0;
        float w = fbm(q * 0.8 + fbm(q * 0.9) * 1.2);
        float lines = 0.5 + 0.5 * sin((w * 9.0 + fbm(q * 1.5) * 0.8) * 6.2832);
        vec3 pink = vec3(1.0, 0.91, 0.90), aqua = vec3(0.84, 0.97, 0.97), cream = vec3(1.0, 0.97, 0.90), lilac = vec3(0.91, 0.91, 1.0);
        vec3 tint = mix(mix(pink, aqua, smoothstep(0.35, 0.65, w)), mix(cream, lilac, smoothstep(0.4, 0.7, fbm(q * 0.7))), 0.5);
        col = cPearl * mix(vec3(1.0), tint, 0.5) * (0.975 + 0.025 * lines);
        col = mix(col, vec3(1.0,0.985,0.96), 0.35 * smoothstep(0.5, 0.85, fbm(q * 0.5 + 2.0)));
        irid = 0.55 + 0.45 * lines;
        rough = 0.12;
      }
    }
    // metal inlay lines between squares
    float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
    float edge = min(min(B.x, 8.0 - B.x), min(B.y, 8.0 - B.y));
    float lw = edge < 0.03 ? lineW * 1.6 : lineW;
    float line = 1.0 - smoothstep(lw * 0.6, lw, d);
    if (line > 0.0) {
      col = mix(col, cMetal, line); metal = max(metal, line); rough = mix(rough, uMetalRough, line);
      height = max(height, line * 0.6 * sqrt(max(0.0, 1.0 - pow(d / lw, 2.0)))); irid *= 1.0 - line;
    }
    // gold beads where four squares meet
    if (uTheme == 0) {
      vec2 cn = abs(f - round(f));
      float rb = length(cn);
      float bead = 1.0 - smoothstep(0.034, 0.042, rb);
      if (bead > 0.0) {
        col = mix(col, cMetal, bead); metal = max(metal, bead); rough = mix(rough, 0.12, bead);
        height = max(height, bead * sqrt(max(0.0, 1.0 - pow(rb / 0.042, 2.0))));
      }
    }
  } else {
    // border band
    vec2 E = B;
    float dIn = max(max(-E.x, E.x - 8.0), max(-E.y, E.y - 8.0));   // 0 at squares, BORDER at rim
    if (uTheme == 0) {
      float g = sin((E.x + E.y) * 6.2832 * 9.0) * sin((E.x - E.y) * 6.2832 * 9.0);
      float wave = sin(dIn * 6.2832 * 18.0 + 0.6 * sin((E.x + E.y) * 12.0));
      col = mix(cA, cB, 0.25 + 0.3 * (0.5 + 0.5 * wave)) * (0.9 + 0.1 * g);
    } else {
      float n = fbm(E * 3.0);
      col = vec3(0.012, 0.013, 0.014) * (0.8 + 0.4 * n);
      col += vec3(0.02, 0.022, 0.02) * smoothstep(0.62, 0.8, fbm(E * 1.4 + 4.0));
      rough = 0.06;
    }
    float rim = smoothstep(BORDER - 0.05, BORDER - 0.035, dIn) + (1.0 - smoothstep(0.0, 0.025, dIn)) * 0.0;
    float inner = 1.0 - smoothstep(0.012, 0.022, abs(dIn - 0.06));
    float outer = 1.0 - smoothstep(0.008, 0.016, abs(dIn - (BORDER - 0.09)));
    float lab = texture2D(uLabels, vUv).r;
    float m = clamp(max(max(rim, inner), max(outer, lab)), 0.0, 1.0);
    col = mix(col, cMetal, m); metal = max(metal, m); rough = mix(rough, uMetalRough, m); height = max(height, m * 0.5);
  }
  if (uMode == 3) {
    // stylised 'beauty' pass for the flat in-app board: lit metal, soft glass sheen
    vec2 gr = vec2(dFdx(height), dFdy(height)) * uBumpK;
    vec3 n = normalize(vec3(-gr, 1.0));
    vec3 L = normalize(vec3(-0.55, 0.6, 0.6));
    float diff = clamp(dot(n, L), 0.0, 1.0);
    float spec = pow(max(dot(reflect(-L, n), vec3(0.0, 0.0, 1.0)), 0.0), 24.0);
    vec3 lit = col * (0.96 + 0.06 * diff);
    vec3 mcol = col * (0.62 + 0.55 * diff) + spec * vec3(1.0, 0.95, 0.85) * 0.9;
    mcol = mix(mcol, col * 1.25, 0.15 * (1.0 - length(gr) * 0.0));
    lit = mix(lit, mcol, metal);
    // broad diagonal sheen like light across glass
    float dg = (vUv.x - vUv.y) * 0.7071;
    float sheen = exp(-pow((dg + 0.18) / 0.22, 2.0)) * 0.07 + exp(-pow((dg + 0.48) / 0.06, 2.0)) * 0.035;
    lit += vec3(1.0, 0.98, 0.95) * sheen * (1.0 - metal * 0.5);
    gl_FragColor = vec4(lit, 1.0);
  }
  else if (uMode == 0) gl_FragColor = vec4(col, 1.0);
  else if (uMode == 1) gl_FragColor = vec4(height, rough, metal, 1.0);
  else gl_FragColor = vec4(irid, irid, irid, 1.0);
}`;

function labelTexture(N) {
  const c = document.createElement('canvas'); c.width = c.height = N; const x = c.getContext('2d');
  x.fillStyle = '#000'; x.fillRect(0, 0, N, N);
  x.fillStyle = '#fff'; x.textAlign = 'center'; x.textBaseline = 'middle';
  const u = N / 9; // one square
  x.font = `500 ${Math.round(u * 0.2)}px "Cormorant Garamond", "Newsreader", Georgia, serif`;
  for (let i = 0; i < (P('labels', 1) ? 8 : 0); i++) {
    const cx = (i + 1) * u;                                   // file letters (canvas y is flipped vs uv)
    x.fillText('abcdefgh'[i], cx, N - u * 0.25);
    x.fillText(String(i + 1), u * 0.25, N - (i + 1) * u);
  }
  const t = new THREE.CanvasTexture(c); t.flipY = true; t.needsUpdate = true; return t;
}

function boardMaterial(labels) {
  return new THREE.ShaderMaterial({
    uniforms: {
      uMode: { value: 0 }, uTheme: { value: TH.rival !== undefined ? 3 : { faberge: 0, malachite: 1, blueprint: 2 }[THEME] }, uRival: { value: TH.rival || 0 }, uMotif: { value: P('motif', TH.motif || 1.0) }, cD: { value: TH.cD || C(1, 1, 1) }, uLabels: { value: labels },
      cA: { value: TH.cA || (THEME === 'faberge' ? TH.enamelDeep : TH.stoneDark) }, cB: { value: TH.cB || (THEME === 'faberge' ? TH.enamelHi : TH.stoneMid) },
      cC: { value: TH.cC || (THEME === 'faberge' ? TH.enamelHi : TH.stoneHi) }, cPearl: { value: TH.pearl }, cMetal: { value: TH.metal }, uMetalRough: { value: TH.metalRough }, uBumpK: { value: P('bk', 6.0) },
    },
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: BOARD_FRAG,
  });
}
function bakeBoard(N = 4096) {
  const labels = labelTexture(N);
  const mat = boardMaterial(labels);
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat);
  const s = new THREE.Scene(); s.add(quad);
  const cam = new THREE.Camera();
  const out = [];
  for (let mode = 0; mode < 3; mode++) {
    const rt = new THREE.WebGLRenderTarget(N, N, { type: THREE.UnsignedByteType, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter, colorSpace: mode === 0 ? THREE.SRGBColorSpace : THREE.NoColorSpace });
    mat.uniforms.uMode.value = mode;
    const tm = renderer.toneMapping; renderer.toneMapping = THREE.NoToneMapping;
    renderer.setRenderTarget(rt); renderer.render(s, cam); renderer.setRenderTarget(null);
    renderer.toneMapping = tm;
    rt.texture.anisotropy = 8;
    out.push(rt.texture);
  }
  return { map: out[0], orm: out[1], irid: out[2] };
}

// ---------------------------------------------------------------- board mesh
const BOARD = 9.0, SLAB = 0.32;
function buildBoard() {
  const tex = bakeBoard(P('tex', 4096));
  const top = new THREE.MeshPhysicalMaterial({
    map: tex.map, roughnessMap: tex.orm, metalnessMap: tex.orm, bumpMap: tex.orm, bumpScale: 0.6,
    roughness: 1, metalness: 1, clearcoat: THEME === 'faberge' ? 1 : 0.7, clearcoatRoughness: 0.03,
    iridescence: THEME === 'malachite' ? 0.9 : 0, iridescenceMap: tex.irid, iridescenceIOR: 1.35, iridescenceThicknessRange: [250, 650],
  });
  // three reads roughness from G and metalness from B of the same texture: exactly our layout
  const plane = new THREE.Mesh(new THREE.PlaneGeometry(BOARD, BOARD), top);
  plane.rotation.x = -Math.PI / 2; plane.position.y = 0.0005; plane.receiveShadow = true; scene.add(plane);
  const frameMat = TH.frame === 'night' ? new THREE.MeshPhysicalMaterial({ color: TH.cC, roughness: 0.15, clearcoat: 1, clearcoatRoughness: 0.03 }) : TH.frame === 'navy' ? new THREE.MeshPhysicalMaterial({ color: C(0.04, 0.09, 0.18), roughness: 0.4, clearcoat: 0.6 }) : TH.frame === 'metal'
    ? new THREE.MeshPhysicalMaterial({ color: C(1.0, 0.76, 0.34), metalness: 1, roughness: 0.2 })
    : new THREE.MeshPhysicalMaterial({ color: C(0.01, 0.011, 0.012), roughness: 0.1, clearcoat: 1, clearcoatRoughness: 0.02 });
  const slab = new THREE.Mesh(new RoundedBoxGeometry(BOARD + 0.16, SLAB, BOARD + 0.16, 6, 0.08), frameMat);
  slab.position.y = -SLAB / 2 - 0.0002; slab.receiveShadow = true; scene.add(slab);
  if (THEME === 'malachite') {
    const rose = new THREE.MeshPhysicalMaterial({ color: TH.metal, metalness: 1, roughness: 0.22 });
    const band = new THREE.Mesh(new RoundedBoxGeometry(BOARD + 0.2, 0.035, BOARD + 0.2, 4, 0.017), rose);
    band.position.y = -SLAB * 0.55; scene.add(band);
  }
  if (TH.beads) {
    // a row of tiny gold beads along the inner edge of the frame
    const bead = new THREE.SphereGeometry(0.026, 20, 12);
    const goldB = new THREE.MeshPhysicalMaterial({ color: C(1.0, 0.77, 0.36), metalness: 1, roughness: 0.14 });
    const n = 28 * 4, inst = new THREE.InstancedMesh(bead, goldB, n * 4); let k = 0; const m4 = new THREE.Matrix4();
    const half = BOARD / 2 - 0.03;
    for (let i = 0; i < n; i++) {
      const t = -half + (i + 0.5) * (2 * half / n);
      for (const [x, z] of [[t, -half], [t, half], [-half, t], [half, t]]) { m4.makeTranslation(x, 0.006, z); inst.setMatrixAt(k++, m4); }
    }
    scene.add(inst);
  }
}

// ---------------------------------------------------------------- pieces
// Every top says what the piece is at phone size, seen from the app's camera (28 degrees up):
// the king a big cross, the queen ball-tipped points around a taller ball, the rook a straight
// tower with four big merlons around a dark well, the bishop a mitre with a deep cut, the knight
// a horse's head, the pawn one ball on a collar. Low plinths, so the mass sits in the tops.
// Heights from the foot, in squares: king 1.30, queen 1.16, bishop 1.00, knight 0.90, rook 0.80, pawn 0.60.
const V2 = (r, y) => new THREE.Vector2(Math.max(0, r), y);
function arc(cx, cy, rad, a0, a1, n = 14) {
  const pts = []; for (let i = 0; i <= n; i++) { const a = (a0 + (a1 - a0) * i / n) * Math.PI / 180; pts.push([cx + Math.cos(a) * rad, cy + Math.sin(a) * rad]); } return pts;
}
function smooth(ctrl, n = 40) { const c = new THREE.SplineCurve(ctrl.map(([r, y]) => V2(r, y))); return c.getPoints(n).map(v => [v.x, v.y]); }
function lathe(pts, seg = TH.facets || 160) { const g = new THREE.LatheGeometry(pts.map(([r, y]) => V2(r, y)), seg); g.computeVertexNormals(); return g; }
// a rounded foot and one bead, then a short step in to the body
function baseProfile(R) {
  return [[0, 0], [R - 0.012, 0], ...arc(R - 0.012, 0.012, 0.012, -90, 0, 6), [R, 0.03],
    ...arc(R - 0.02, 0.052, 0.022, -65, 90, 14), [R - 0.035, 0.074], [R * 0.86, 0.08]];
}
// a collar disc of radius rc from y to y + h, back to the neck radius rn
function collar(rn, y, rc, h) { return [[rc - 0.012, y], [rc, y + 0.012], [rc, y + h - 0.012], [rc - 0.012, y + h], [rn, y + h + 0.004]]; }
function torus(R, tube, y, mat) { const t = new THREE.Mesh(new THREE.TorusGeometry(R, tube, 24, 180), mat); t.rotation.x = Math.PI / 2; t.position.y = y; t.castShadow = true; return t; }
function sphere(r, y, mat) { const m = new THREE.Mesh(new THREE.SphereGeometry(r, 48, 32), mat); m.position.y = y; m.castShadow = true; return m; }
function mesh(g, mat) { const m = new THREE.Mesh(g, mat); m.castShadow = true; m.receiveShadow = true; return m; }
function addBase(g, M, R) { g.add(torus(R - 0.01, 0.012, 0.03, M.trim)); }
// a trim ring around the body at radius r, set in so the body still makes the outline
function band(g, M, r, y) { g.add(torus(r - 0.008, 0.012, y, M.trim)); }
// a material of its own (for clipping), keeping any shader patch
function own(m) { const c = m.clone(); c.onBeforeCompile = m.onBeforeCompile; c.customProgramCacheKey = m.customProgramCacheKey; return c; }

// The sprite camera's right and up directions: the bishop's cut runs along its line of sight,
// so the cut shows in the outline.
const EL = P('el', 28) * Math.PI / 180;
const CAM_X = new THREE.Vector3(1, 0, 0), CAM_U = new THREE.Vector3(0, Math.cos(EL), -Math.sin(EL));
// Clips away a slot through the screen point (cx, cy): `width` wide, rising to the right at `angle`,
// from the right edge to `stop` (along the slot) past that point.
function slotPlanes(cx, cy, angle, width, stop) {
  const n = CAM_X.clone().multiplyScalar(-Math.sin(angle)).add(CAM_U.clone().multiplyScalar(Math.cos(angle)));
  const d = CAM_X.clone().multiplyScalar(Math.cos(angle)).add(CAM_U.clone().multiplyScalar(Math.sin(angle)));
  const c = CAM_X.clone().multiplyScalar(cx).add(CAM_U.clone().multiplyScalar(cy));
  const nc = n.dot(c), dc = d.dot(c);
  return [new THREE.Plane(n.clone().negate(), nc - width / 2), new THREE.Plane(n.clone(), -(nc + width / 2)), new THREE.Plane(d.clone().negate(), dc + stop)];
}
function clipped(m, planes) {
  m.material = own(m.material); m.material.clipIntersection = true; m.material.clipShadows = true;
  m.userData.clip = planes; return m;
}

// Shared with the Blueprint ink. Seen from 28 degrees the rook's back merlons stand higher than its
// middle, so the rook is kept low enough to stay clearly under the knight on screen, and the mitre is
// stretched to stand clearly over it.
const ROOK = { top: 0.6, rIn: 0.19, rOut: 0.268, mh: 0.14 };
const mitreY = y => 0.438 + (y - 0.438) * 1.07;

const builders = {
  pawn(M) {
    const g = new THREE.Group(), R = 0.25;
    const prof = [...baseProfile(R), ...smooth([[R * 0.86, 0.082], [0.17, 0.13], [0.122, 0.19], [0.098, 0.25]], 18),
      ...collar(0.098, 0.255, 0.158, 0.042), [0.085, 0.307], ...arc(0, 0.462, 0.155, -56.7, 90, 40)];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R);
    band(g, M, 0.158, 0.276);
    return g;
  },
  rook(M) {
    const g = new THREE.Group(), R = 0.285, { top, rIn, rOut, mh } = ROOK, p = top - 0.05;
    const prof = [...baseProfile(R), [0.243, 0.085], [0.228, p - 0.045],
      ...smooth([[0.228, p - 0.042], [0.243, p - 0.023], [0.263, p - 0.007]], 8), [rOut, p], [rOut, top], [rIn, top]];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R);
    // the dark well inside the battlements
    g.add(mesh(lathe([[rIn, top], [rIn, top - 0.075], [0, top - 0.075]]), M.well));
    band(g, M, rOut, p);
    // four big square merlons, the notches at the front, back and sides, so they show from the camera
    const half = P('mw', 25) * Math.PI / 180, bv = 0.004, cs = TH.facets ? 2 : 20;
    for (let i = 0; i < 4; i++) {
      const a = Math.PI / 4 + i * Math.PI / 2;
      const sh = new THREE.Shape(); sh.absarc(0, 0, rOut - bv, a - half, a + half, false); sh.absarc(0, 0, rIn + bv, a + half, a - half, true);
      const eg = new THREE.ExtrudeGeometry(sh, { depth: mh - 2 * bv, bevelEnabled: true, bevelThickness: bv, bevelSize: bv, bevelSegments: 3, curveSegments: cs });
      const m = mesh(eg, M.body); m.rotation.x = -Math.PI / 2; m.position.y = top - 0.004 + bv; g.add(m);
      // a cap on each merlon
      const ch = half - 0.035, ct = 0.007;
      const s2 = new THREE.Shape(); s2.absarc(0, 0, rOut - 0.008, a - ch, a + ch, false); s2.absarc(0, 0, rIn + 0.008, a + ch, a - ch, true);
      const cg = new THREE.ExtrudeGeometry(s2, { depth: ct, bevelEnabled: true, bevelThickness: 0.004, bevelSize: 0.006, bevelSegments: 3, curveSegments: cs });
      const c = mesh(cg, M.cap); c.rotation.x = -Math.PI / 2; c.position.y = top - 0.004 + mh + 0.004; g.add(c);
    }
    return g;
  },
  bishop(M) {
    const g = new THREE.Group(), R = 0.275;
    const prof = [...baseProfile(R), ...smooth([[R * 0.86, 0.082], [0.185, 0.13], [0.135, 0.22], [0.1, 0.32], [0.088, 0.385]], 20),
      ...collar(0.088, 0.39, 0.152, 0.042), [0.092, 0.44], [0.0, 0.44]];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); band(g, M, 0.152, 0.411);
    // the mitre, a tall upright egg, with a deep cut that runs along the camera's line of sight
    const mp = [[0.0, 0.438], [0.092, 0.438], ...smooth([[0.094, 0.444], [0.13, 0.5], [0.16, 0.58], [0.165, 0.645], [0.149, 0.735], [0.108, 0.815], [0.06, 0.872], [0.015, 0.906]], 40), [0.0, 0.912]].map(([r, y]) => [r, mitreY(y)]);
    const cut = { x: P('bcx', 0.055), y: P('bcy', 0.612), a: P('bca', 36) * Math.PI / 180, w: P('bcw', 0.08), stop: P('bcs', -0.105) };
    g.add(clipped(mesh(lathe(mp), M.body), slotPlanes(cut.x, cut.y, cut.a, cut.w, cut.stop)));
    // lined: a slightly smaller core shows along both edges of the cut
    const core = mp.map(([r, y]) => [r * 0.94, y]);
    g.add(clipped(mesh(lathe(core), M.lining), slotPlanes(cut.x, cut.y, cut.a, cut.w - 0.032, cut.stop + 0.014)));
    g.add(sphere(0.048, mitreY(0.912) + 0.042, M.tip));
    return g;
  },
  queen(M) {
    const g = new THREE.Group(), R = 0.3;
    const prof = [...baseProfile(R), ...smooth([[R * 0.86, 0.082], [0.195, 0.15], [0.14, 0.28], [0.11, 0.43], [0.107, 0.525]], 30),
      ...collar(0.107, 0.53, 0.172, 0.044), [0.112, 0.582],
      ...smooth([[0.112, 0.588], [0.133, 0.65], [0.17, 0.73], [0.203, 0.795]], 20), [0.211, 0.808], [0.211, 0.826], [0.195, 0.834],
      ...smooth([[0.177, 0.836], [0.13, 0.858], [0.065, 0.884], [0.0, 0.892]], 16)];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); band(g, M, 0.172, 0.552);
    band(g, M, 0.211, 0.817);
    // the coronet: ball-tipped points leaning out from the rim, around a taller ball
    const n = P('qn', 8), lean = P('ql', 0.34), len = P('qlen', 0.135), r0 = 0.195, y0 = 0.818;
    for (let i = 0; i < n; i++) {
      const a = (i + 0.5) / n * Math.PI * 2;
      const out = new THREE.Vector3(Math.sin(a), 0, Math.cos(a)), tan = new THREE.Vector3(Math.cos(a), 0, -Math.sin(a));
      const sp = mesh(new THREE.ConeGeometry(0.04, len, TH.facets || 32), M.crown);
      sp.quaternion.setFromAxisAngle(tan, lean);
      const mid = out.clone().multiplyScalar(r0 + Math.sin(lean) * len / 2); mid.y = y0 + Math.cos(lean) * len / 2;
      sp.position.copy(mid); g.add(sp);
      const tip = out.clone().multiplyScalar(r0 + Math.sin(lean) * len); tip.y = y0 + Math.cos(lean) * len;
      const s = sphere(0.038, 0, M.gem); s.position.copy(tip); g.add(s);
    }
    const stem = mesh(new THREE.CylinderGeometry(0.03, 0.054, 0.2, TH.facets || 32), M.crown); stem.position.y = 0.97; g.add(stem);
    g.add(sphere(0.066, 1.097, M.crown));
    return g;
  },
  king(M) {
    const g = new THREE.Group(), R = 0.31;
    const prof = [...baseProfile(R), ...smooth([[R * 0.86, 0.082], [0.2, 0.16], [0.146, 0.3], [0.115, 0.46], [0.113, 0.575]], 30),
      ...collar(0.113, 0.58, 0.18, 0.046), [0.117, 0.634],
      ...smooth([[0.117, 0.64], [0.144, 0.7], [0.183, 0.78], [0.21, 0.848]], 20), [0.218, 0.86], [0.218, 0.878], [0.198, 0.886],
      ...smooth([[0.18, 0.888], [0.133, 0.91], [0.075, 0.933], [0.0, 0.942]], 16)];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); band(g, M, 0.18, 0.603);
    band(g, M, 0.218, 0.869);
    // a big, thick cross: arms much wider than the stem
    const cw = P('kcw', 0.105), cd = 0.095;
    const v = mesh(new RoundedBoxGeometry(cw, 0.37, cd, 4, 0.024), M.cross); v.position.y = 0.93 + 0.185; g.add(v);
    const h = mesh(new RoundedBoxGeometry(P('kca', 0.33), cw, cd, 4, 0.024), M.cross); h.position.y = 1.165; g.add(h);
    const gem = mesh(new THREE.OctahedronGeometry(0.042), M.gem); gem.position.set(0, 1.165, cd / 2 + 0.004); gem.scale.set(1, 1, 0.45); g.add(gem);
    return g;
  },
  knight(M) {
    const g = new THREE.Group(), R = 0.29, Y = 0.17;
    const prof = [...baseProfile(R), ...smooth([[R * 0.86, 0.082], [0.228, 0.115], [0.215, 0.15]], 6), [0.228, 0.158], [0.228, Y + 0.002], [0.0, Y + 0.002]];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); band(g, M, 0.228, Y - 0.006);
    // the horse's head in profile (x forward, y up): back of the neck, a tall ear, brow, long nose,
    // muzzle, open mouth, jaw, throat
    const s = new THREE.Shape();
    s.moveTo(-0.2, 0.0);
    s.bezierCurveTo(-0.25, 0.17, -0.23, 0.37, -0.14, 0.53);      // back of the neck
    s.bezierCurveTo(-0.11, 0.585, -0.085, 0.62, -0.065, 0.65);    // up to the poll
    s.lineTo(-0.035, 0.75);                                      // ear tip
    s.bezierCurveTo(-0.01, 0.725, 0.01, 0.69, 0.018, 0.655);      // front of the ear
    s.bezierCurveTo(0.045, 0.668, 0.085, 0.665, 0.115, 0.643);    // brow
    s.bezierCurveTo(0.18, 0.596, 0.255, 0.5, 0.3, 0.415);         // nose ridge
    s.bezierCurveTo(0.326, 0.372, 0.338, 0.33, 0.32, 0.302);      // muzzle
    s.lineTo(0.245, 0.293);                                      // into the mouth
    s.lineTo(0.292, 0.262);                                      // lower lip
    s.bezierCurveTo(0.288, 0.238, 0.258, 0.226, 0.222, 0.232);    // chin
    s.bezierCurveTo(0.165, 0.24, 0.105, 0.25, 0.075, 0.278);      // under the jaw
    s.bezierCurveTo(0.035, 0.245, 0.03, 0.185, 0.072, 0.135);     // throat
    s.bezierCurveTo(0.135, 0.085, 0.188, 0.048, 0.2, 0.0);        // chest
    s.lineTo(0.2, -0.05); s.lineTo(-0.2, -0.05);                // down into the base, out of sight
    const head = horseHead(s, M);
    head.mesh.position.y = Y; g.add(head.mesh);
    // the eyes, a gem in a dark socket, and the nostrils, set into the carved faces
    for (const z of [-1, 1]) {
      const ze = head.surf(0.122, 0.565), zn = head.surf(0.287, 0.385);
      const sock = sphere(0.034, 0, M.well); sock.scale.set(1.3, 0.9, 0.3); sock.position.set(0.12, Y + 0.565, z * (ze - 0.004)); g.add(sock);
      const e = sphere(0.023, 0, M.eye); e.scale.set(1.15, 0.95, 0.5); e.position.set(0.124, Y + 0.565, z * (ze + 0.0005)); g.add(e);
      const nos = sphere(0.018, 0, M.well); nos.scale.set(1.25, 0.75, 0.3); nos.position.set(0.287, Y + 0.385, z * (zn - 0.004)); nos.rotation.z = -0.5; g.add(nos);
    }
    g.userData.surf = head.surf; g.userData.Y = Y;
    return g;
  },
};

// ---------------------------------------------------------------- the knight's head
// Lawson flips: turns a triangulation of points inside an outline into a Delaunay one, so the
// carved faces shade smoothly. T holds counter-clockwise triangles [a, b, c] of the points P.
function delaunay(P, T) {
  const inCircle = (a, b, c, d) => {
    const ax = P[a][0] - P[d][0], ay = P[a][1] - P[d][1], bx = P[b][0] - P[d][0], by = P[b][1] - P[d][1], cx = P[c][0] - P[d][0], cy = P[c][1] - P[d][1];
    return (ax * ax + ay * ay) * (bx * cy - cx * by) - (bx * bx + by * by) * (ax * cy - cx * ay) + (cx * cx + cy * cy) * (ax * by - bx * ay);
  };
  const has = (t, a, b) => (t[0] === a && t[1] === b) || (t[1] === a && t[2] === b) || (t[2] === a && t[0] === b);
  for (let pass = 0; pass < 200; pass++) {
    const edges = new Map(); let flips = 0;
    T.forEach((t, i) => { for (let e = 0; e < 3; e++) { const a = t[e], b = t[(e + 1) % 3], k = Math.min(a, b) * 1e6 + Math.max(a, b); const v = edges.get(k); if (v) v.push(i); else edges.set(k, [i]); } });
    const busy = new Uint8Array(T.length);
    for (const [k, ts] of edges) {
      if (ts.length !== 2 || busy[ts[0]] || busy[ts[1]]) continue;
      let a = Math.floor(k / 1e6), b = k % 1e6, [t1, t2] = ts;
      if (!has(T[t1], a, b)) [a, b] = [b, a];
      if (!has(T[t1], a, b) || !has(T[t2], b, a)) continue;
      const c = T[t1].find(v => v !== a && v !== b), d = T[t2].find(v => v !== a && v !== b);
      if (inCircle(a, b, c, d) > 1e-13) { T[t1] = [a, d, c]; T[t2] = [d, b, c]; busy[t1] = busy[t2] = 1; flips++; }
    }
    if (!flips) break;
  }
  return T;
}

// The head carved from its profile: straight walls `wall` either side of the middle, and faces that
// round over from the outline (upright there) to a gently domed side `rz` higher, `rd` in from the edge,
// with the cheek, brow, eye socket and nostril modelled in. Along the back of the neck, a mane of
// scalloped locks in the accent material, the notches between them carried across as grooves.
function horseHead(shape, M) {
  const wall = 0.058, rz = 0.052, rd = 0.06, step = 0.0105;
  const nLocks = P('nl', 6), lockA = P('la', 0.021), maneW = P('mw2', 0.062);
  // the outline, about 4 thousandths apart; the first two curves are the back of the neck
  const pts = [], back = [];
  shape.curves.forEach((cv, ci) => {
    const n = Math.max(2, Math.ceil(cv.getLength() / 0.004));
    const sp = cv.getSpacedPoints(n); sp.pop();
    sp.forEach(p => { pts.push([p.x, p.y]); if (ci < 2) back.push([p.x, p.y]); });
  });
  back.push([pts[back.length][0], pts[back.length][1]]);
  // arc length along the back; the mane runs from `m0` of the way up to the poll
  const bl = [0]; for (let i = 1; i < back.length; i++) bl.push(bl[i - 1] + Math.hypot(back[i][0] - back[i - 1][0], back[i][1] - back[i - 1][1]));
  const m0 = 0.16, BL = bl[bl.length - 1];
  const uOf = i => (bl[i] / BL - m0) / (1 - m0);
  const outN = i => { const a = back[Math.max(0, i - 1)], b = back[Math.min(back.length - 1, i + 1)]; const dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy); return [-dy / l, dx / l]; };
  // scallop the back: each lock a rounded bump, a notch between them
  const lockBump = u => { if (u <= 0 || u >= 1) return 0; const f = (u * nLocks) % 1; return lockA * Math.pow(Math.sin(Math.PI * f), 0.55) * (0.55 + 0.45 * Math.sin(Math.PI * u)); };
  for (let i = 0; i < back.length - 1; i++) { const u = uOf(i), [nx, ny] = outN(i), b = lockBump(u); pts[i][0] += nx * b; pts[i][1] += ny * b; }
  // counter-clockwise
  let area = 0; for (let i = 0; i < pts.length; i++) { const a = pts[i], b = pts[(i + 1) % pts.length]; area += a[0] * b[1] - b[0] * a[1]; }
  const flip = area < 0, N = pts.length;
  if (flip) pts.reverse();
  // the mane: within maneW of the (unscalloped) back, between u = 0 and 1, its inner edge in lobes
  const maneWidth = u => maneW * (0.5 + 0.5 * Math.pow(Math.sin(Math.PI * Math.min(1, Math.max(0, u))), 0.6)) * (1 - 0.18 * Math.cos(2 * Math.PI * nLocks * u));
  const backNear = (x, y) => {
    let m = Infinity, bi = 0, bt = 0;
    for (let i = 0; i < back.length - 1; i++) {
      const a = back[i], b = back[i + 1], ex = b[0] - a[0], ey = b[1] - a[1];
      let t = ((x - a[0]) * ex + (y - a[1]) * ey) / (ex * ex + ey * ey); t = Math.min(1, Math.max(0, t));
      const d = (x - a[0] - ex * t) ** 2 + (y - a[1] - ey * t) ** 2; if (d < m) { m = d; bi = i; bt = t; }
    }
    return [Math.sqrt(m), uOf(bi) + (uOf(bi + 1) - uOf(bi)) * bt];
  };
  const inMane = (x, y) => { const [d, u] = backNear(x, y); return u > 0 && u < 1 && d < maneWidth(u); };
  // the grooves between the locks, from each notch in across the mane, sweeping down
  const grooves = [];
  for (let k = 1; k < nLocks; k++) {
    const u = k / nLocks, t = m0 + u * (1 - m0); let i = bl.findIndex(v => v / BL >= t); i = Math.max(1, i);
    const [nx, ny] = outN(i), w = maneWidth(u);
    grooves.push([[back[i][0], back[i][1]], [back[i][0] - nx * w * 1.05 - ny * 0.012, back[i][1] - ny * w * 1.05 + nx * 0.012]]);
  }
  const segD = (x, y, a, b) => { const ex = b[0] - a[0], ey = b[1] - a[1]; let t = ((x - a[0]) * ex + (y - a[1]) * ey) / (ex * ex + ey * ey); t = Math.min(1, Math.max(0, t)); return Math.hypot(x - a[0] - ex * t, y - a[1] - ey * t); };
  // the modelling: [x, y, radius, height]
  const bumps = [[0.135, 0.37, 0.085, 0.02], [0.27, 0.355, 0.045, 0.008], [0.2, 0.5, 0.05, 0.006], [0.098, 0.615, 0.035, 0.007],
    [0.12, 0.565, 0.03, -0.016], [0.287, 0.385, 0.02, -0.012], [-0.06, 0.26, 0.12, 0.01]];
  const near = (x, y) => {
    let m = Infinity;
    for (let i = 0; i < N; i++) {
      const a = pts[i], b = pts[(i + 1) % N], ex = b[0] - a[0], ey = b[1] - a[1];
      let t = ((x - a[0]) * ex + (y - a[1]) * ey) / (ex * ex + ey * ey); t = Math.min(1, Math.max(0, t));
      const d = (x - a[0] - ex * t) ** 2 + (y - a[1] - ey * t) ** 2; if (d < m) m = d;
    }
    return Math.sqrt(m);
  };
  const inside = (x, y) => { let c = false; for (let i = 0, j = N - 1; i < N; j = i++) { const a = pts[i], b = pts[j]; if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) c = !c; } return c; };
  const height = (x, y) => {
    const d = near(x, y), s = Math.min(d / rd, 1), ss = s * s * (3 - 2 * s);
    let h = rz * Math.sqrt(1 - (1 - s) * (1 - s));
    for (const [bx, by, br, bh] of bumps) h += bh * ss * Math.exp(-((x - bx) ** 2 + (y - by) ** 2) / (br * br));
    for (const [a, b] of grooves) h -= 0.007 * Math.min(1, d / 0.012) * Math.exp(-((segD(x, y, a, b) / 0.0055) ** 2));
    return h;
  };
  // points inside: a staggered grid, plus a row along the mane's inner edge so the gold follows it
  const S = [];
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  pts.forEach(([x, y]) => { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); });
  const seam = [];
  for (let i = 0; i < back.length - 1; i += 1) {
    const u = uOf(i); if (u <= 0.01 || u >= 0.99) continue;
    const [nx, ny] = outN(i), w = maneWidth(u); seam.push([back[i][0] - nx * w, back[i][1] - ny * w]);
  }
  const seamPts = [];
  seam.forEach(p => { if (!seamPts.length || Math.hypot(p[0] - seamPts[seamPts.length - 1][0], p[1] - seamPts[seamPts.length - 1][1]) > 0.0045) seamPts.push(p); });
  const nearSeam = (x, y) => seamPts.some(p => Math.hypot(x - p[0], y - p[1]) < step * 0.55);
  // (a little jitter keeps the grid points off each other's lines)
  const jit = (i, j) => (Math.sin(i * 127.1 + j * 311.7) * 43758.5453 % 1) * step * 0.05;
  for (let r = 0, y = y0 + step / 2; y < y1; y += step * 0.866, r++)
    for (let c = 0, x = x0 + (r % 2 ? step / 2 : 0); x < x1; x += step, c++) {
      const px = x + jit(r, c), py = y + jit(c + 7, r);
      if (inside(px, py) && near(px, py) > step * 0.5 && !nearSeam(px, py)) S.push([px, py]);
    }
  seamPts.forEach(p => { if (inside(p[0], p[1]) && near(p[0], p[1]) > step * 0.35) S.push(p); });
  // triangulate the outline alone, drop each inner point into the triangle that holds it, then flip
  // to a Delaunay triangulation (the outline's edges stay)
  const PP = pts.concat(S);
  const orient = (p, q, r) => (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]);
  let T = THREE.ShapeUtils.triangulateShape(pts.map(([x, y]) => new THREE.Vector2(x, y)), [])
    .map(([a, b, c]) => (orient(PP[a], PP[b], PP[c]) > 0 ? [a, b, c] : [a, c, b]));
  for (let k = N; k < PP.length; k++) {
    const p = PP[k]; let best = -1, bestMin = -Infinity;
    for (let t = 0; t < T.length; t++) {
      const [a, b, c] = T[t], A = PP[a], B = PP[b], Cc = PP[c];
      if (p[0] < Math.min(A[0], B[0], Cc[0]) - 1e-9 || p[0] > Math.max(A[0], B[0], Cc[0]) + 1e-9 || p[1] < Math.min(A[1], B[1], Cc[1]) - 1e-9 || p[1] > Math.max(A[1], B[1], Cc[1]) + 1e-9) continue;
      const ar = orient(A, B, Cc), w = Math.min(orient(A, B, p), orient(B, Cc, p), orient(Cc, A, p)) / ar;
      if (w > bestMin) { bestMin = w; best = t; }
    }
    if (best < 0 || bestMin <= 1e-12) continue;
    const [a, b, c] = T[best];
    T[best] = [a, b, k]; T.push([b, c, k], [c, a, k]);
  }
  T = delaunay(PP, T);
  // vertices: front face (outline, then inner points), back face the same mirrored
  const V = PP.length, pos = new Float32Array(V * 2 * 3), nor = new Float32Array(V * 2 * 3), e = 0.0012;
  const H = PP.map(([x, y], i) => (i < N ? 0 : height(x, y)));
  for (let i = 0; i < V; i++) {
    const [x, y] = PP[i]; let nx, ny, nz;
    if (i < N) {
      const a = PP[(i - 1 + N) % N], b = PP[(i + 1) % N], dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy);
      nx = dy / l; ny = -dx / l; nz = 0;
    } else {
      const gx = (height(x + e, y) - height(x - e, y)) / (2 * e), gy = (height(x, y + e) - height(x, y - e)) / (2 * e);
      const l = Math.hypot(gx, gy, 1); nx = -gx / l; ny = -gy / l; nz = 1 / l;
    }
    const z = wall + H[i];
    pos.set([x, y, z], i * 3); nor.set([nx, ny, nz], i * 3);
    pos.set([x, y, -z], (V + i) * 3); nor.set([nx, ny, -nz], (V + i) * 3);
  }
  const body = [], mane = [];
  const put = (tri3, cx, cy) => (inMane(cx, cy) ? mane : body).push(...tri3);
  for (const [a, b, c] of T) {
    const cx = (PP[a][0] + PP[b][0] + PP[c][0]) / 3, cy = (PP[a][1] + PP[b][1] + PP[c][1]) / 3;
    put([a, b, c], cx, cy); put([V + a, V + c, V + b], cx, cy);
  }
  for (let i = 0; i < N; i++) {
    const j = (i + 1) % N, mx = (PP[i][0] + PP[j][0]) / 2, my = (PP[i][1] + PP[j][1]) / 2;
    const dx = PP[j][0] - PP[i][0], dy = PP[j][1] - PP[i][1], l = Math.hypot(dx, dy);
    const cx = mx - dy / l * 0.006, cy = my + dx / l * 0.006;       // a little inside, to pick the material
    put([i, V + i, V + j], cx, cy); put([i, V + j, j], cx, cy);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3)); geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  geo.setIndex(body.concat(mane)); geo.addGroup(0, body.length, 0); geo.addGroup(body.length, mane.length, 1);
  const m = new THREE.Mesh(geo, [M.body, M.mane]); m.castShadow = true; m.receiveShadow = true;
  return { mesh: m, surf: (x, y) => wall + height(x, y) };
}


// ---------------------------------------------------------------- blueprint detail: inked contours and carving
function tube(pts, r, mat) {
  const c = new THREE.CatmullRomCurve3(pts.map(p => p.isVector3 ? p : new THREE.Vector3(...p)));
  return mesh(new THREE.TubeGeometry(c, Math.max(24, pts.length * 3), r, 8, false), mat);
}
function lathes(g) { return g.children.filter(o => o.geometry && o.geometry.type === 'LatheGeometry'); }
function radiusAt(pts, y) {
  let best = 0;
  for (let i = 0; i < pts.length - 1; i++) { const a = pts[i], b = pts[i + 1];
    if ((a.y - y) * (b.y - y) <= 0 && a.y !== b.y) { const t = (y - a.y) / (b.y - a.y); best = Math.max(best, a.x + (b.x - a.x) * t); } }
  return best;
}
const INK = P('ink', 0.0042);
// lines down the turned surface of lathe `li` (0 = the body), between y0 and y1
function meridians(g, M, n, y0, y1, li = 0) {
  const lm = lathes(g)[li]; if (!lm) return;
  const pts = lm.geometry.parameters.points.filter(v => v.y >= y0 && v.y <= y1 && v.x > 0.02);
  for (let k = 0; k < n; k++) {
    const a = (k + 0.5) / n * Math.PI * 2;
    g.add(tube(pts.map(v => [Math.sin(a) * (v.x + 0.003), v.y, Math.cos(a) * (v.x + 0.003)]), INK * 0.8, M.ink));
  }
}
function ring(g, M, y, extra = 0.003, r = INK, li = 0) { const lm = lathes(g)[li]; const R = radiusAt(lm.geometry.parameters.points, y) + extra; g.add(torus(R, r, y, M.ink)); }
function arcTube(R, y, a0, a1, mat, r = INK) { const pts = []; for (let i = 0; i <= 24; i++) { const a = a0 + (a1 - a0) * i / 24; pts.push([Math.cos(a) * R, y, Math.sin(a) * R]); } return tube(pts, r, mat); }

const DETAIL = {
  pawn(g, M) { meridians(g, M, 10, 0.09, 0.25); ring(g, M, 0.15); ring(g, M, 0.21); meridians(g, M, 6, 0.34, 0.585); ring(g, M, 0.455); },
  rook(g, M) {
    const pts = lathes(g)[0].geometry.parameters.points;
    // masonry: courses of stone with staggered joints on the tower
    const wallTop = ROOK.top - 0.095, slitY = 0.33, courses = [0, 1, 2, 3, 4, 5, 6].map(i => 0.1 + (wallTop - 0.1) * i / 6);
    courses.forEach(y => ring(g, M, y));
    for (let c = 0; c < courses.length - 1; c++) {
      const ya = courses[c], yb = courses[c + 1], n = 10, off = c % 2 ? Math.PI / n : 0;
      for (let k = 0; k < n; k++) { const a = k / n * Math.PI * 2 + off;
        const seg = []; for (let i = 0; i <= 4; i++) { const y = ya + (yb - ya) * i / 4; const r = radiusAt(pts, y) + 0.003; seg.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
        g.add(tube(seg, INK * 0.8, M.ink)); }
    }
    // arrow slits, front and sides
    for (const a of [0, Math.PI * 0.62, -Math.PI * 0.62]) {
      const r = radiusAt(pts, slitY);
      const slit = mesh(new RoundedBoxGeometry(0.032, 0.09, 0.03, 3, 0.012), M.socket);
      slit.position.set(Math.sin(a) * (r - 0.006), slitY, Math.cos(a) * (r - 0.006)); slit.rotation.y = a; g.add(slit);
      const fr = new THREE.Shape(); fr.absarc(0, 0.027, 0.022, 0, Math.PI, false); fr.lineTo(-0.022, -0.052); fr.lineTo(0.022, -0.052); fr.lineTo(0.022, 0.027);
      const outline = fr.getPoints(24).map(v => new THREE.Vector3(v.x, v.y, 0));
      const o = tube([...outline, outline[0]], INK * 0.7, M.ink); o.position.set(Math.sin(a) * (r + 0.004), slitY, Math.cos(a) * (r + 0.004)); o.rotation.y = a; g.add(o);
    }
    // the parapet and every merlon outlined in ink
    ring(g, M, ROOK.top - 0.04); ring(g, M, ROOK.top - 0.005);
    const half = P('mw', 25) * Math.PI / 180, top = ROOK.top, mh = ROOK.mh;
    for (let i = 0; i < 4; i++) { const a = Math.PI / 4 + i * Math.PI / 2;
      for (const s of [-1, 1]) { const e = -(a + s * half);
        g.add(tube([[Math.cos(e) * 0.253, top, Math.sin(e) * 0.253], [Math.cos(e) * 0.253, top + mh - 0.004, Math.sin(e) * 0.253]], INK * 0.8, M.ink)); }
      g.add(arcTube(0.253, top + 0.07, -(a + half), -(a - half), M.ink, INK * 0.7)); }
  },
  bishop(g, M) {
    meridians(g, M, 10, 0.09, 0.39); ring(g, M, 0.2); ring(g, M, 0.3);
    // the mitre: curved gores sweeping up to the tip
    const pts = lathes(g)[1].geometry.parameters.points;
    for (let k = 0; k < 8; k++) {
      const seg = []; for (let i = 0; i <= 20; i++) { const y = mitreY(0.47 + (0.88 - 0.47) * i / 20), tw = (i / 20) * 0.9;
        const a = k / 8 * Math.PI * 2 + tw; const r = radiusAt(pts, y) + 0.003; seg.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
      g.add(tube(seg, INK * 0.75, M.ink));
    }
    ring(g, M, mitreY(0.48), 0.003, INK * 1.2, 1);
    for (let k = 0; k < 12; k++) { const a = k / 12 * Math.PI * 2; const b = sphere(0.011, 0.411, M.trim); b.position.x = Math.cos(a) * 0.152; b.position.z = Math.sin(a) * 0.152; g.add(b); }
  },
  queen(g, M) {
    meridians(g, M, 12, 0.09, 0.525); ring(g, M, 0.25); ring(g, M, 0.42);
    const pts = lathes(g)[0].geometry.parameters.points;
    for (let k = 0; k < 10; k++) { const a = (k + 0.5) / 10 * Math.PI * 2;
      const seg = []; for (let i = 0; i <= 12; i++) { const y = 0.6 + (0.795 - 0.6) * i / 12; const r = radiusAt(pts, y) + 0.003; seg.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
      g.add(tube(seg, INK * 0.8, M.ink)); }
    ring(g, M, 0.7);
  },
  king(g, M) {
    meridians(g, M, 12, 0.09, 0.575); ring(g, M, 0.25); ring(g, M, 0.44);
    const pts = lathes(g)[0].geometry.parameters.points;
    for (let k = 0; k < 12; k++) { const a = (k + 0.5) / 12 * Math.PI * 2;
      const seg = []; for (let i = 0; i <= 12; i++) { const y = 0.65 + (0.848 - 0.65) * i / 12; const r = radiusAt(pts, y) + 0.003; seg.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
      g.add(tube(seg, INK * 0.8, M.ink)); }
    ring(g, M, 0.75);
  },
  knight(g, M) {
    const Y = g.userData.Y, surf = g.userData.surf;
    meridians(g, M, 12, 0.02, 0.15);
    // ink lines lie on the carved faces
    const side = (pts2, r = INK, mat = M.ink) => { for (const z of [-1, 1]) g.add(tube(pts2.map(([x, y]) => [x, y + Y, z * (surf(x, y) + 0.0015)]), r, mat)); };
    const curve = (ctrl, n = 24) => new THREE.SplineCurve(ctrl.map(([x, y]) => new THREE.Vector2(x, y))).getPoints(n).map(v => [v.x, v.y]);
    side(curve([[0.065, 0.552], [0.095, 0.578], [0.14, 0.578], [0.168, 0.555]]), INK * 1.1);         // upper lid
    side(curve([[0.075, 0.54], [0.112, 0.524], [0.152, 0.535]]), INK * 0.8);                         // lower lid
    side(curve([[0.06, 0.6], [0.11, 0.612], [0.16, 0.6], [0.2, 0.57]]), INK * 0.7);                  // brow ridge
    side(curve([[0.25, 0.36], [0.272, 0.393], [0.298, 0.38]]), INK * 0.8);                           // nostril
    side(curve([[0.3, 0.3], [0.27, 0.296], [0.24, 0.3], [0.21, 0.312]]), INK);                       // mouth
    side(curve([[0.205, 0.3], [0.16, 0.315], [0.1, 0.33], [0.06, 0.37], [0.065, 0.43], [0.1, 0.46], [0.15, 0.45]], 40), INK * 1.05);   // cheek
    side(curve([[0.08, 0.632], [0.15, 0.58], [0.22, 0.5], [0.27, 0.43]]), INK * 0.7);                // nose ridge
    side(curve([[-0.045, 0.648], [-0.025, 0.705], [-0.01, 0.7], [0.012, 0.648]]), INK * 0.9);         // ear fold
    side(curve([[0.02, 0.645], [0.065, 0.615], [0.1, 0.6]]), INK * 1.6, M.trim);                    // amber brow band
  },
};


// ---------------------------------------------------------------- fine detail (every set but Blueprint)
// What a jeweller adds once the shapes read: pearl beading round the foot and the collars, gadrooned
// crown cups, cabochons on the king's crown, arrow slits in the rook. All small, none of it changes the
// outline the pieces are told apart by.
function beadRing(g, mat, r, y, n, size) {
  const geo = new THREE.SphereGeometry(size, 12, 8);
  for (let k = 0; k < n; k++) { const a = k / n * Math.PI * 2; const b = mesh(geo, mat); b.position.set(Math.sin(a) * r, y, Math.cos(a) * r); g.add(b); }
}
// lobes standing out of lathe `li` between y0 and y1
function gadroon(g, n, y0, y1, depth, li = 0) {
  if (TH.facets) return;
  const geo = lathes(g)[li].geometry, pos = geo.attributes.position;
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
    if (y <= y0 || y >= y1) continue;
    const r = Math.hypot(x, z); if (r < 1e-4) continue;
    const t = (y - y0) / (y1 - y0), w = Math.pow(Math.sin(Math.PI * t), 0.7), a = Math.atan2(x, z);
    const k = (r + depth * w * (Math.pow(Math.abs(Math.cos(n * a / 2)), 0.8) - 0.7)) / r;
    pos.setX(i, x * k); pos.setZ(i, z * k);
  }
  pos.needsUpdate = true; geo.computeVertexNormals();
}
function footBeads(g, M, R) { beadRing(g, M.trim, R - 0.024, 0.071, Math.round(Math.PI * 2 * (R - 0.024) / 0.019), 0.0085); }
const FINE = {
  pawn(g, M) { footBeads(g, M, 0.25); },
  knight(g, M) { footBeads(g, M, 0.29); beadRing(g, M.trim, 0.229, 0.172, 44, 0.0085); },
  bishop(g, M) { footBeads(g, M, 0.275); beadRing(g, M.trim, 0.146, 0.436, 30, 0.0085); },
  rook(g, M) {
    footBeads(g, M, 0.285);
    const pts = lathes(g)[0].geometry.parameters.points, y = 0.32;
    // two string courses in the trim round the tower
    for (const yy of [0.19, 0.45]) g.add(torus(radiusAt(pts, yy) + 0.001, 0.0065, yy, M.trim));
    // arrow slits front, back and sides, dark like the well
    for (let i = 0; i < 4; i++) { const a = i * Math.PI / 2, r = radiusAt(pts, y);
      const slit = mesh(new RoundedBoxGeometry(0.032, 0.13, 0.03, 4, 0.0155), M.well);
      slit.position.set(Math.sin(a) * (r - 0.008), y, Math.cos(a) * (r - 0.008)); slit.rotation.y = a; g.add(slit); }
  },
  queen(g, M) {
    footBeads(g, M, 0.3); gadroon(g, 16, 0.6, 0.79, 0.009);
    beadRing(g, M.trim, 0.168, 0.578, 34, 0.0088);
  },
  king(g, M) {
    footBeads(g, M, 0.31); gadroon(g, 18, 0.652, 0.842, 0.01);
    beadRing(g, M.trim, 0.176, 0.629, 36, 0.009);
    const pts = lathes(g)[0].geometry.parameters.points, y = 0.76;
    for (let i = 0; i < 4; i++) { const a = i * Math.PI / 2, r = radiusAt(pts, y) + 0.004;
      const c = sphere(0.022, 0, M.gem); c.scale.set(1, 1.25, 0.5); c.position.set(Math.sin(a) * r, y, Math.cos(a) * r); c.rotation.y = a; g.add(c); }
  },
};

// ---------------------------------------------------------------- materials per side
// Light pieces darken toward their outline, as a real ivory piece falls into shade at its edges,
// so they keep a contour on light squares. Dark pieces keep their outline bright from the strip
// lights behind them (makeEnv). Each theme may set `edge: { w: [floor, width], b: ... }`.
// `rim` [strength, width, color] adds the light of a strip behind the piece along a dark outline:
// strongest on the sides, softer over the top, none at the foot.
function edgeShade(mat, edge, rim) {
  const m = mat.clone();
  const [floor, width, lo = 0] = edge || [1, 0.5];
  const [rk, rw, rc] = rim || [0, 0.5, 0xffffff];
  m.onBeforeCompile = sh => {
    Object.assign(sh.uniforms, { uEdgeFloor: { value: floor }, uEdgeWidth: { value: width }, uEdgeLo: { value: lo }, uRimK: { value: rk }, uRimW: { value: rw }, uRimC: { value: new THREE.Color(rc) } });
    // applied after tone mapping, so it changes what is shown even on the brightest pieces
    sh.fragmentShader = 'uniform float uEdgeFloor;\nuniform float uEdgeWidth;\nuniform float uEdgeLo;\nuniform float uRimK;\nuniform float uRimW;\nuniform vec3 uRimC;\n' + sh.fragmentShader.replace('#include <opaque_fragment>', `
      vec3 vdE = isOrthographic ? vec3(0.0, 0.0, 1.0) : normalize(vViewPosition);
      vec3 nnE = normalize(normal);
      float nvE = clamp(abs(dot(nnE, vdE)), 0.0, 1.0);
      float edgeK = mix(uEdgeFloor, 1.0, smoothstep(uEdgeLo, uEdgeWidth, nvE));
      float sideE = clamp(abs(nnE.x) * 1.1 + max(nnE.y, 0.0) * 0.6, 0.0, 1.0);
      vec3 rimE = uRimC * uRimK * sideE * pow(1.0 - smoothstep(0.0, uRimW, nvE), 1.5);
      #include <opaque_fragment>`).replace('#include <tonemapping_fragment>', `#include <tonemapping_fragment>
      gl_FragColor.rgb = gl_FragColor.rgb * edgeK + rimE;`);
  };
  m.customProgramCacheKey = () => ['edge', floor, width, lo, rk, rw, rc].join(':');
  return m;
}
// the rook's well and the knight's eye sockets: matte, so they read as shadow
const WELL = new THREE.MeshStandardMaterial({ color: C(0.004, 0.004, 0.005), roughness: 0.95, metalness: 0, envMapIntensity: 0.3 });
// Roles: body and trim, then what marks each piece: the king's cross, the queen's crown and gems,
// the rook's merlon caps, the bishop's tip and cut lining, the knight's mane and eye. Each falls back
// to `accent`, and `accent` to `trim`.
function sideMats(side) {
  const base = TH.mats()[side], memo = new Map();
  const edge = (TH.edge && side in TH.edge) ? TH.edge[side] : (side === 'w' ? [P('ef', 0.3), P('ew', 0.5), P('elo', 0)] : null);
  const rim = side === 'b' ? (TH.rim || [P('rk', 0), P('rw', 0.5), TH.env.cool]) : null;
  const fix = m => {
    if (!memo.has(m)) memo.set(m, (edge || (rim && rim[0] > 0)) && m.isMeshStandardMaterial ? edgeShade(m, edge, rim) : m);
    return memo.get(m);
  };
  const out = {};
  for (const [k, m] of Object.entries(base)) out[k] = fix(m);
  out.accent = out.accent || out.trim; out.well = out.well || WELL;
  for (const r of ['cross', 'crown', 'cap', 'tip', 'lining', 'mane']) out[r] = out[r] || out.accent;
  out.gem = out.gem || out.accent; out.eye = out.eye || out.gem;
  return out;
}
const MATS = { w: sideMats('w'), b: sideMats('b') };

let KNIGHT_PROFILE = false;
function piece(type, side, x, z, rotY = 0) {
  const g = builders[type](MATS[side]);
  g.position.set(x, 0, z);
  if (TH.wire) DETAIL[type](g, MATS[side]);
  else if (!Q.has('plain')) FINE[type](g, MATS[side]);
  if (type === 'knight') g.rotation.y = rotY + (KNIGHT_PROFILE ? Math.PI + P('kr', 0.3) : (side === 'w' ? P('kw', 2.25) : P('kb', -2.0)));
  else g.rotation.y = rotY;
  scene.add(g);
  // clipping planes live in world space: move them with the piece
  g.updateMatrixWorld(true);
  g.traverse(o => { if (o.userData.clip) o.material.clippingPlanes = o.userData.clip.map(p => p.clone().applyMatrix4(o.matrixWorld)); });
  return g;
}
const sq = s => [s.charCodeAt(0) - 97 - 3.5, 3.5 - (+s[1] - 1)];

// ---------------------------------------------------------------- lights
function lights(shadowSize = 4096) {
  const key = new THREE.DirectionalLight(TH.env.warm, P('key', 2.2));
  key.position.set(-5, 11, 6);
  key.castShadow = true;
  key.shadow.mapSize.set(shadowSize, shadowSize);
  Object.assign(key.shadow.camera, { left: -6, right: 6, top: 6, bottom: -6, near: 1, far: 30 });
  key.shadow.radius = 6; key.shadow.bias = -0.0004; key.shadow.normalBias = 0.01;
  scene.add(key);
  const rim = new THREE.DirectionalLight(TH.env.cool, P('rim', 0.9)); rim.position.set(6, 5, -8); scene.add(rim);
}
// Sprites: a key from the front left, low enough that the right side of each piece falls into soft
// shade (flutes, crown points and the knight's face read); a light from straight above casts the
// short contact shadow; a rim from behind right picks out the tops.
// For the dark side, two kickers from behind and a little below light the left and right edges.
function spriteLights() {
  const key = new THREE.DirectionalLight(TH.env.warm, P('key', 2.0)); key.position.set(-6, 7, 6); scene.add(key);
  const top = new THREE.DirectionalLight(0xffffff, P('top', 0.6)); top.position.set(-0.6, 12, 1.2);
  top.castShadow = true; top.shadow.mapSize.set(2048, 2048);
  Object.assign(top.shadow.camera, { left: -1.2, right: 1.2, top: 1.2, bottom: -1.2, near: 1, far: 30 });
  top.shadow.radius = 8; top.shadow.bias = -0.0004; top.shadow.normalBias = 0.01; scene.add(top);
  const rim = new THREE.DirectionalLight(TH.env.cool, P('rim', 0.9)); rim.position.set(6, 5, -8); scene.add(rim);
  const kick = P('kk', TH.kick ?? 3);
  const kl = new THREE.DirectionalLight(TH.env.cool, kick); kl.position.set(-5, -3.5, -8);
  const kr = new THREE.DirectionalLight(TH.env.warm, kick); kr.position.set(5, -3.5, -8);
  scene.add(kl); scene.add(kr);
  // For the light side, a soft fill from beside the camera: faces turned to the viewer brighten while the
  // edges, turned away, stay darker, so a light piece keeps its outline on light squares.
  const fill = new THREE.DirectionalLight(0xffffff, P('ff', TH.frontFill ?? 1.0)); fill.position.set(-1.5, 5.5, 9); scene.add(fill);
  return { kickers: [kl, kr], fills: [fill] };
}

// ---------------------------------------------------------------- contour
// A fine shade just inside the outline, the same width on screen whatever the shape (`width` px of the
// sprite, down to `floor` of the color at the very edge, easing back over `soft` px). It keeps a light
// piece's contour on a light square as bright as the piece itself. The piece's own colors are kept,
// only darker, so it reads as shading rather than a drawn line.
function contour(src, width, floor, soft = 1.5) {
  const w = src.width, h = src.height;
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const x = c.getContext('2d'); x.drawImage(src, 0, 0);
  const im = x.getImageData(0, 0, w, h), d = im.data;
  // the piece is what is clearly opaque; the contact shadow stays below half
  const inside = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) inside[i] = d[i * 4 + 3] > 160 ? 1 : 0;
  const R = Math.ceil(width + soft + 1), offs = [];
  for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) { const r = Math.hypot(dx, dy); if (r <= R) offs.push([dx, dy, r]); }
  offs.sort((a, b) => a[2] - b[2]);
  for (let y = 0; y < h; y++) for (let px = 0; px < w; px++) {
    const i = y * w + px; if (d[i * 4 + 3] === 0) continue;
    let dist = R;
    if (!inside[i]) dist = 0;
    else for (const [dx, dy, r] of offs) {
      const X = px + dx, Y = y + dy;
      if (X < 0 || Y < 0 || X >= w || Y >= h || !inside[Y * w + X]) { dist = r; break; }
    }
    const t = Math.min(1, Math.max(0, (dist - width) / soft + 0.5));
    const k = floor + (1 - floor) * t * t * (3 - 2 * t);
    d[i * 4] *= k; d[i * 4 + 1] *= k; d[i * 4 + 2] *= k;
  }
  x.putImageData(im, 0, 0);
  return c.toDataURL('image/png');
}

// ---------------------------------------------------------------- shots
const FEN = Q.get('fen') || 'r2q1rk1/pp2bppp/2n1bn2/3p4/3P4/2NBBN2/PP3PPP/R2Q1RK1';
const TYPES = { p: 'pawn', r: 'rook', n: 'knight', b: 'bishop', q: 'queen', k: 'king' };
function setupFen(fen) {
  fen.split('/').forEach((row, ri) => { let f = 0; for (const ch of row) { if (/\d/.test(ch)) f += +ch; else { const side = ch === ch.toUpperCase() ? 'w' : 'b'; piece(TYPES[ch.toLowerCase()], side, f - 3.5, ri - 3.5); f++; } } });
}

async function main() {
  await document.fonts.load('500 40px "Cormorant Garamond"').catch(() => {});
  renderer.localClippingEnabled = true;
  let camera;
  if (SHOT === 'hero') {
    buildBoard(); lights(); setupFen(FEN);
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), new THREE.ShadowMaterial({ opacity: 0.55 }));
    floor.rotation.x = -Math.PI / 2; floor.position.y = -SLAB; floor.receiveShadow = true; scene.add(floor);
    const bg = document.createElement('canvas'); bg.width = 512; bg.height = 288; const bx = bg.getContext('2d');
    const gr = bx.createRadialGradient(256, 90, 10, 256, 140, 330);
    const [c0, c1] = { faberge: ['#1a2a6a', '#03050f'], malachite: ['#0f4a33', '#020805'], blueprint: ['#1d3c66', '#050c18'] }[THEME] || [ '#' + TH.cB.clone().multiplyScalar(0.45).getHexString(), '#' + TH.cC.clone().multiplyScalar(0.6).getHexString() ];
    gr.addColorStop(0, c0); gr.addColorStop(1, c1); bx.fillStyle = gr; bx.fillRect(0, 0, 512, 288);
    const bt = new THREE.CanvasTexture(bg); bt.colorSpace = THREE.SRGBColorSpace; scene.background = bt;
    camera = new THREE.PerspectiveCamera(P('fov', 24), W / H, 0.1, 100);
    camera.position.set(P('cx', 3.2), P('cy', 4.6), P('cz', 11.5)); camera.lookAt(P('tx', 0.2), P('ty', 0.2), P('tz', 0.6));
  } else if (SHOT === 'board') {
    const mat = boardMaterial(labelTexture(W)); mat.uniforms.uMode.value = 3;
    const s2 = new THREE.Scene(); s2.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat));
    renderer.toneMapping = THREE.NoToneMapping; renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
    renderer.render(s2, new THREE.Camera()); window.__done = true; return;
  } else if (SHOT === 'lineup') {
    KNIGHT_PROFILE = true;
    buildBoard(); lights();
    const order = ['pawn', 'knight', 'bishop', 'rook', 'queen', 'king'];
    order.forEach((t, i) => { piece(t, 'w', i - 2.5, 0.5); piece(t, 'b', i - 2.5, -0.6); });
    scene.background = new THREE.Color(0x050506);
    camera = new THREE.PerspectiveCamera(P('fov', 26), W / H, 0.1, 100);
    camera.position.set(0, P('cy', 2.6), P('cz', 9)); camera.lookAt(0, 0.45, 0);
  } else if (SHOT === 'sprites') {
    KNIGHT_PROFILE = true;
    // each piece on a shadow catcher, seen from the app's camera angle, transparent background
    const envs = { w: makeEnv('w'), b: makeEnv('b') };
    // a black flag keeps the reflector card off the dark bodies (the knight's side would mirror it as a
    // flat brown); the gold and other metal parts still see it
    const flagged = makeEnv('b', false);
    for (const m of new Set(Object.values(MATS.b))) if (m.isMeshStandardMaterial && m.metalness < 0.5 && m !== WELL) m.envMap = flagged;
    const rig = spriteLights();
    // the contact shadow fades out well inside the picture
    const shadowMat = new THREE.ShadowMaterial({ opacity: P('so', 0.5) });
    shadowMat.onBeforeCompile = sh => {
      sh.vertexShader = 'varying vec2 vFloor;\n' + sh.vertexShader.replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\n  vFloor = (modelMatrix * vec4(transformed, 1.0)).xz;');
      sh.fragmentShader = 'varying vec2 vFloor;\n' + sh.fragmentShader.replace('opacity * ( 1.0 - getShadowMask() )', 'opacity * ( 1.0 - getShadowMask() ) * ( 1.0 - smoothstep(0.3, 0.6, length(vFloor)) )');
    };
    const catcher = new THREE.Mesh(new THREE.PlaneGeometry(6, 6), shadowMat);
    catcher.rotation.x = -Math.PI / 2; catcher.receiveShadow = true; scene.add(catcher);
    const bottom = P('sb', -0.4), top = P('st', 1.5), hw = P('hw', 0.7); // sprite units: 1 = one square width
    camera = new THREE.OrthographicCamera(-hw, hw, top, bottom, 0.1, 50);
    const dist = 10; camera.position.set(0, Math.sin(EL) * dist, Math.cos(EL) * dist); camera.lookAt(0, 0, 0);
    const only = Q.get('only') ? Q.get('only').split(',') : null;
    const out = [];
    for (const side of ['w', 'b']) {
      scene.environment = envs[side];
      rig.kickers.forEach(l => { l.visible = side === 'b'; });
      rig.fills.forEach(l => { l.visible = side === 'w'; });
      for (const t of ['king', 'queen', 'rook', 'bishop', 'knight', 'pawn']) {
        const code = side + ({ king: 'K', queen: 'Q', rook: 'R', bishop: 'B', knight: 'N', pawn: 'P' })[t];
        if (only && !only.includes(code)) continue;
        const g = piece(t, side, 0, 0);
        renderer.render(scene, camera);
        const line = Q.has('lw') ? (side === 'w' && +Q.get('lw') > 0 ? [P('lw', 0), P('lf', 0.4), P('ls', 1.5)] : null) : (TH.contour && TH.contour[side]);
        out.push([code, line ? contour(renderer.domElement, ...line) : renderer.domElement.toDataURL('image/png')]);
        scene.remove(g);
      }
    }
    window.__png = out; window.__done = true; return;
  }
  renderer.render(scene, camera);
  window.__done = true;
}
main();
