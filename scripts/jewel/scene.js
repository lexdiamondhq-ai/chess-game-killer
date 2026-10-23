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
function makeEnv() {
  const es = new THREE.Scene();
  const T = THEMES[THEME].env;
  es.add(new THREE.Mesh(new THREE.SphereGeometry(50, 32, 16), new THREE.MeshBasicMaterial({ color: new THREE.Color(T.room), side: THREE.BackSide })));
  const panel = (w, h, col, k, pos, rot) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(col).multiplyScalar(k), side: THREE.DoubleSide }));
    m.position.set(...pos); m.rotation.set(...rot); es.add(m);
  };
  if (SHOT !== 'board') panel(14, 8, 0xffffff, 3.0, [-3, 12, -2], [Math.PI / 2, 0, 0.5]);      // big top softbox
  else panel(30, 30, 0xffffff, 0.06, [0, 14, 0], [Math.PI / 2, 0, 0]);
  panel(3, 16, T.warm, 4.0, [-14, 5, 2], [0, Math.PI / 2, 0]);           // warm strip left
  panel(3, 16, T.cool, 2.6, [14, 5, -2], [0, -Math.PI / 2, 0]);          // cool strip right
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
      return { w: { body: gold, trim: pearl, gem: sapphire, eye: sapphire }, b: { body: midnight, trim: gold, gem: diamond, eye: gold } };
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
    pearl: C(1, 0.9, 0.7), metal: C(1.0, 0.74, 0.28), metalRough: 0.2, frame: 'night', motif: 0.9,
    mats: () => {
      const ember = new THREE.MeshPhysicalMaterial({ color: C(1.0, 0.82, 0.5), roughness: 0.16, clearcoat: 1, clearcoatRoughness: 0.03, emissive: C(0.28, 0.09, 0.0), sheen: 0.4, sheenColor: C(1, 0.8, 0.4) });
      const obsidian = new THREE.MeshPhysicalMaterial({ color: C(0.025, 0.018, 0.014), roughness: 0.1, clearcoat: 1, clearcoatRoughness: 0.02 });
      const gold = new THREE.MeshPhysicalMaterial({ color: C(1.0, 0.76, 0.32), metalness: 1, roughness: 0.18, envMapIntensity: 2.0 });
      const glow = new THREE.MeshBasicMaterial({ color: C(1.0, 0.6, 0.15) });
      return { w: { body: ember, trim: gold, gem: glow, eye: gold }, b: { body: obsidian, trim: gold, gem: glow, eye: gold } };
    },
  },
  drift: {
    rival: 1, env: { room: 0x101820, warm: 0xd8c0ff, cool: 0x9ffff0 },
    cA: C(0.03, 0.085, 0.12), cB: C(0.33, 0.66, 0.66), cC: C(0.015, 0.04, 0.06), cD: C(1.0, 0.55, 0.85),
    pearl: C(0.8, 1, 0.97), metal: C(0.78, 0.58, 1.0), metalRough: 0.2, frame: 'night', motif: 1.0,
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
    pearl: C(0.85, 0.97, 1), metal: C(0.3, 0.88, 1.0), metalRough: 0.2, frame: 'night', motif: 0.9,
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
const V2 = (r, y) => new THREE.Vector2(Math.max(0, r), y);
function arc(cx, cy, rad, a0, a1, n = 14) {
  const pts = []; for (let i = 0; i <= n; i++) { const a = (a0 + (a1 - a0) * i / n) * Math.PI / 180; pts.push([cx + Math.cos(a) * rad, cy + Math.sin(a) * rad]); } return pts;
}
function smooth(ctrl, n = 40) { const c = new THREE.SplineCurve(ctrl.map(([r, y]) => V2(r, y))); return c.getPoints(n).map(v => [v.x, v.y]); }
function lathe(pts, seg = TH.facets || 160) { const g = new THREE.LatheGeometry(pts.map(([r, y]) => V2(r, y)), seg); g.computeVertexNormals(); return g; }
function baseProfile(R) {
  return [[0, 0], [R - 0.012, 0], ...arc(R - 0.012, 0.012, 0.012, -90, 0, 6), [R, 0.03],
    ...arc(R - 0.03, 0.062, 0.032, -70, 90, 16), [R - 0.06, 0.098], ...smooth([[R - 0.06, 0.1], [R * 0.84, 0.112], [R * 0.78, 0.13]], 10)];
}
function torus(R, tube, y, mat) { const t = new THREE.Mesh(new THREE.TorusGeometry(R, tube, 24, 180), mat); t.rotation.x = Math.PI / 2; t.position.y = y; t.castShadow = true; return t; }
function sphere(r, y, mat) { const m = new THREE.Mesh(new THREE.SphereGeometry(r, 48, 32), mat); m.position.y = y; m.castShadow = true; return m; }
function mesh(g, mat) { const m = new THREE.Mesh(g, mat); m.castShadow = true; m.receiveShadow = true; return m; }

function collar(g, M, y, R) {
  g.add(torus(R, 0.019, y, M.trim));
  g.add(torus(R * 0.86, 0.008, y + 0.03, M.trim));
}
function addBase(g, M, R) { g.add(torus(R - 0.03, 0.033, 0.062, M.trim)); }

const builders = {
  pawn(M) {
    const g = new THREE.Group(), R = 0.255;
    const prof = [...baseProfile(R), ...smooth([[R * 0.72, 0.14], [0.13, 0.19], [0.095, 0.26], [0.082, 0.33]], 20),
      [0.13, 0.338], [0.14, 0.35], [0.14, 0.365], [0.13, 0.375], [0.075, 0.385], ...arc(0, 0.5, 0.136, -58, 90, 40)];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); g.add(torus(0.135, 0.021, 0.357, M.trim));
    return g;
  },
  rook(M) {
    const g = new THREE.Group(), R = 0.305;
    const prof = [...baseProfile(R), ...smooth([[R * 0.72, 0.15], [0.19, 0.22], [0.165, 0.34], [0.17, 0.44], [0.195, 0.5]], 24),
      [0.235, 0.51], [0.24, 0.53], [0.235, 0.545], [0.21, 0.553], [0.212, 0.66], [0.236, 0.67], [0.24, 0.69], [0.0, 0.69]];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); g.add(torus(0.238, 0.019, 0.53, M.trim));
    g.add(torus(0.218, 0.008, 0.6, M.trim));
    for (let i = 0; i < 6; i++) {
      const a0 = i * Math.PI / 3 + 0.12, a1 = a0 + Math.PI / 3 - 0.24;
      const sh = new THREE.Shape(); sh.absarc(0, 0, 0.24, a0, a1, false); sh.absarc(0, 0, 0.165, a1, a0, true);
      const eg = new THREE.ExtrudeGeometry(sh, { depth: 0.085, bevelEnabled: true, bevelThickness: 0.008, bevelSize: 0.008, bevelSegments: 4, curveSegments: 24 });
      const m = mesh(eg, M.body); m.rotation.x = -Math.PI / 2; m.position.y = 0.685; g.add(m);
    }
    return g;
  },
  bishop(M) {
    const g = new THREE.Group(), R = 0.285;
    const prof = [...baseProfile(R), ...smooth([[R * 0.72, 0.15], [0.13, 0.22], [0.095, 0.33], [0.085, 0.45]], 20),
      [0.14, 0.462], [0.155, 0.478], [0.155, 0.49], [0.14, 0.502], [0.088, 0.51],
      ...smooth([[0.088, 0.515], [0.12, 0.565], [0.142, 0.64], [0.135, 0.72], [0.1, 0.8], [0.055, 0.87], [0.018, 0.912]], 40), [0.012, 0.918], ...arc(0, 0.948, 0.034, -68, 90, 20)];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); g.add(torus(0.152, 0.02, 0.482, M.trim));
    const slit = mesh(new THREE.CylinderGeometry(0.143, 0.143, 0.018, 128), M.trim); slit.position.y = 0.69; slit.rotation.z = 0.62; g.add(slit);
    g.add(sphere(0.04, 0.95, M.trim));
    return g;
  },
  queen(M) {
    const g = new THREE.Group(), R = 0.33;
    const prof = [...baseProfile(R), ...smooth([[R * 0.72, 0.15], [0.15, 0.24], [0.105, 0.4], [0.095, 0.55], [0.11, 0.62]], 30),
      [0.165, 0.635], [0.178, 0.652], [0.178, 0.664], [0.165, 0.678], [0.118, 0.686], ...smooth([[0.118, 0.69], [0.135, 0.74], [0.17, 0.81], [0.2, 0.865]], 20),
      [0.205, 0.875], [0.19, 0.886], ...smooth([[0.15, 0.89], [0.11, 0.91], [0.06, 0.94], [0.0, 0.955]], 16)];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); g.add(torus(0.175, 0.021, 0.657, M.trim));
    g.add(torus(0.2, 0.014, 0.878, M.trim));
    for (let i = 0; i < 8; i++) {
      const a = i / 8 * Math.PI * 2, o = 0.32;  // each point leans out a little
      const spike = mesh(new THREE.ConeGeometry(0.034, 0.13, 32), M.body);
      spike.position.set(Math.cos(a) * 0.205, 0.93, Math.sin(a) * 0.205);
      spike.rotation.set(Math.sin(a) * o, 0, -Math.cos(a) * o); g.add(spike);
      const s = sphere(0.03, 0.995, M.gem); s.position.x = Math.cos(a) * 0.227; s.position.z = Math.sin(a) * 0.227; g.add(s);
    }
    const stem = mesh(new THREE.CylinderGeometry(0.018, 0.034, 0.09, 32), M.trim); stem.position.y = 0.99; g.add(stem);
    g.add(sphere(0.054, 1.07, M.trim));
    return g;
  },
  king(M) {
    const g = new THREE.Group(), R = 0.35;
    const prof = [...baseProfile(R), ...smooth([[R * 0.72, 0.15], [0.16, 0.25], [0.115, 0.42], [0.105, 0.6], [0.12, 0.665]], 30),
      [0.18, 0.68], [0.193, 0.697], [0.193, 0.709], [0.18, 0.723], [0.128, 0.732], ...smooth([[0.128, 0.736], [0.145, 0.79], [0.18, 0.86], [0.205, 0.905]], 20),
      [0.21, 0.915], [0.19, 0.926], ...smooth([[0.15, 0.93], [0.11, 0.955], [0.07, 0.99], [0.0, 1.0]], 16)];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); g.add(torus(0.19, 0.022, 0.702, M.trim));
    g.add(torus(0.205, 0.014, 0.918, M.trim));
    const v = mesh(new RoundedBoxGeometry(0.082, 0.25, 0.082, 4, 0.022), M.trim); v.position.y = 1.075; g.add(v);
    const h = mesh(new RoundedBoxGeometry(0.24, 0.082, 0.082, 4, 0.022), M.trim); h.position.y = 1.115; g.add(h);
    const gem = mesh(new THREE.OctahedronGeometry(0.038), M.gem); gem.position.set(0, 1.115, 0.045); gem.scale.set(1, 1, 0.5); g.add(gem);
    return g;
  },
  knight(M) {
    const g = new THREE.Group(), R = 0.31;
    const prof = [...baseProfile(R), [R * 0.74, 0.15], [0.23, 0.165], [0.0, 0.165]];
    g.add(mesh(lathe(prof), M.body)); addBase(g, M, R); g.add(torus(0.225, 0.016, 0.158, M.trim));
    // horse head silhouette (x forward, y up)
    const s = new THREE.Shape();
    s.moveTo(-0.2, 0.0);
    s.bezierCurveTo(-0.23, 0.16, -0.22, 0.34, -0.13, 0.5);
    s.bezierCurveTo(-0.09, 0.57, -0.06, 0.62, -0.035, 0.7);   // back of neck to poll
    s.lineTo(-0.01, 0.76);                                   // ear tip
    s.bezierCurveTo(0.01, 0.73, 0.03, 0.69, 0.05, 0.665);    // front of ear
    s.bezierCurveTo(0.12, 0.64, 0.2, 0.56, 0.27, 0.44);      // forehead and nose ridge
    s.bezierCurveTo(0.3, 0.39, 0.32, 0.36, 0.305, 0.33);     // muzzle
    s.bezierCurveTo(0.29, 0.3, 0.25, 0.29, 0.22, 0.305);     // lip
    s.bezierCurveTo(0.17, 0.33, 0.12, 0.33, 0.08, 0.32);     // jaw
    s.bezierCurveTo(0.04, 0.3, 0.05, 0.24, 0.1, 0.19);       // throat
    s.bezierCurveTo(0.16, 0.13, 0.2, 0.07, 0.2, 0.0);        // chest
    s.lineTo(-0.2, 0.0);
    const depth = P('kd', 0.12);
    const eg = new THREE.ExtrudeGeometry(s, { depth, bevelEnabled: true, bevelThickness: 0.05, bevelSize: 0.045, bevelSegments: 12, curveSegments: 48 });
    eg.translate(0, 0, -depth / 2); eg.computeVertexNormals();
    const head = mesh(eg, M.body); head.position.y = 0.16; g.add(head);
    // mane: a row of trim beads along the back of the neck
    const mc = new THREE.CubicBezierCurve3(new THREE.Vector3(-0.215, 0.2, 0), new THREE.Vector3(-0.235, 0.36, 0), new THREE.Vector3(-0.18, 0.52, 0), new THREE.Vector3(-0.07, 0.66, 0));
    for (let i = 0; i <= 9; i++) { const pt = mc.getPoint(i / 9); const b = sphere(0.03 - i * 0.0012, 0, M.trim); b.position.set(pt.x - 0.012, pt.y + 0.16, 0); g.add(b); }
    for (const z of [-1, 1]) { const e = sphere(0.019, 0, M.eye); e.position.set(0.12, 0.16 + 0.55, z * (depth / 2 + 0.042)); e.scale.set(1.3, 0.8, 0.6); g.add(e); }
    // bridle band
    const br = mesh(new THREE.TorusGeometry(0.105, 0.011, 16, 80), M.trim); br.position.set(0.19, 0.16 + 0.42, 0); br.rotation.set(0, Math.PI / 2, -0.6); br.scale.set(1, 1.0, 1); g.add(br);
    return g;
  },
};


// ---------------------------------------------------------------- blueprint detail: inked contours and carving
function tube(pts, r, mat) {
  const c = new THREE.CatmullRomCurve3(pts.map(p => p.isVector3 ? p : new THREE.Vector3(...p)));
  return mesh(new THREE.TubeGeometry(c, Math.max(24, pts.length * 3), r, 8, false), mat);
}
function latheOf(g) { let m = null; g.children.forEach(o => { if (!m && o.geometry && o.geometry.type === 'LatheGeometry') m = o; }); return m; }
function radiusAt(pts, y) {
  let best = 0;
  for (let i = 0; i < pts.length - 1; i++) { const a = pts[i], b = pts[i + 1];
    if ((a.y - y) * (b.y - y) <= 0 && a.y !== b.y) { const t = (y - a.y) / (b.y - a.y); best = Math.max(best, a.x + (b.x - a.x) * t); } }
  return best;
}
const INK = P('ink', 0.0042);
function meridians(g, M, n, y0, y1) {
  const lm = latheOf(g); if (!lm) return;
  const pts = lm.geometry.parameters.points.filter(v => v.y >= y0 && v.y <= y1 && v.x > 0.02);
  for (let k = 0; k < n; k++) {
    const a = (k + 0.5) / n * Math.PI * 2;
    g.add(tube(pts.map(v => [Math.sin(a) * (v.x + 0.003), v.y, Math.cos(a) * (v.x + 0.003)]), INK * 0.8, M.ink));
  }
}
function ring(g, M, y, extra = 0.003, r = INK) { const lm = latheOf(g); const R = radiusAt(lm.geometry.parameters.points, y) + extra; g.add(torus(R, r, y, M.ink)); }
function arcTube(R, y, a0, a1, mat, r = INK) { const pts = []; for (let i = 0; i <= 24; i++) { const a = a0 + (a1 - a0) * i / 24; pts.push([Math.cos(a) * R, y, Math.sin(a) * R]); } return tube(pts, r, mat); }

const DETAIL = {
  pawn(g, M) { meridians(g, M, 10, 0.13, 0.34); ring(g, M, 0.2); ring(g, M, 0.3); meridians(g, M, 6, 0.39, 0.625); g.add(torus(0.139, INK, 0.5, M.ink)); },
  rook(g, M) {
    const pts = latheOf(g).geometry.parameters.points;
    meridians(g, M, 12, 0.12, 0.21);
    // masonry: courses of stone with staggered joints on the tower and the turret
    const courses = [0.235, 0.29, 0.345, 0.4, 0.455, 0.5];
    courses.forEach(y => ring(g, M, y));
    for (let c = 0; c < courses.length - 1; c++) {
      const ya = courses[c], yb = courses[c + 1], n = 10, off = c % 2 ? Math.PI / n : 0;
      for (let k = 0; k < n; k++) { const a = k / n * Math.PI * 2 + off;
        const seg = []; for (let i = 0; i <= 4; i++) { const y = ya + (yb - ya) * i / 4; const r = radiusAt(pts, y) + 0.003; seg.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
        g.add(tube(seg, INK * 0.8, M.ink)); }
    }
    const tc = [0.565, 0.61, 0.655];
    tc.forEach(y => ring(g, M, y));
    for (let c = 0; c < tc.length - 1; c++) { const n = 12, off = c % 2 ? Math.PI / n : 0;
      for (let k = 0; k < n; k++) { const a = k / n * Math.PI * 2 + off, r = 0.215;
        g.add(tube([[Math.sin(a) * r, tc[c], Math.cos(a) * r], [Math.sin(a) * r, tc[c + 1], Math.cos(a) * r]], INK * 0.8, M.ink)); } }
    // arrow slits in the tower, front and sides
    for (const a of [0, Math.PI * 0.62, -Math.PI * 0.62]) {
      const r = radiusAt(pts, 0.37);
      const slit = mesh(new RoundedBoxGeometry(0.03, 0.085, 0.03, 3, 0.012), M.socket);
      slit.position.set(Math.sin(a) * (r - 0.006), 0.37, Math.cos(a) * (r - 0.006)); slit.rotation.y = a; g.add(slit);
      const fr = new THREE.Shape(); fr.absarc(0, 0.025, 0.021, 0, Math.PI, false); fr.lineTo(-0.021, -0.05); fr.lineTo(0.021, -0.05); fr.lineTo(0.021, 0.025);
      const outline = fr.getPoints(24).map(v => new THREE.Vector3(v.x, v.y, 0));
      const o = tube([...outline, outline[0]], INK * 0.7, M.ink); o.position.set(Math.sin(a) * (r + 0.004), 0.37, Math.cos(a) * (r + 0.004)); o.rotation.y = a; g.add(o);
    }
    // battlements: ink along the top of every merlon and around the inner floor
    for (let i = 0; i < 6; i++) { const a0 = i * Math.PI / 3 + 0.12, a1 = a0 + Math.PI / 3 - 0.24;
      g.add(arcTube(0.247, 0.776, -a1, -a0, M.ink)); g.add(arcTube(0.158, 0.776, -a1, -a0, M.ink));
      for (const a of [a0, a1]) g.add(tube([[Math.cos(-a) * 0.247, 0.69, Math.sin(-a) * 0.247], [Math.cos(-a) * 0.247, 0.776, Math.sin(-a) * 0.247]], INK * 0.8, M.ink)); }
    g.add(torus(0.15, INK, 0.693, M.ink));
  },
  bishop(g, M) {
    meridians(g, M, 10, 0.13, 0.46); ring(g, M, 0.3);
    // the mitre: curved gores sweeping up to the finial, and a deep cut slit
    const pts = latheOf(g).geometry.parameters.points;
    for (let k = 0; k < 8; k++) {
      const seg = []; for (let i = 0; i <= 20; i++) { const y = 0.52 + (0.9 - 0.52) * i / 20, tw = (i / 20) * 0.9;
        const a = k / 8 * Math.PI * 2 + tw; const r = radiusAt(pts, y) + 0.003; seg.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
      g.add(tube(seg, INK * 0.75, M.ink));
    }
    ring(g, M, 0.53, 0.003, INK * 1.2);
    g.children.filter(o => o.geometry && o.geometry.type === 'CylinderGeometry').forEach(o => { o.material = M.socket; o.scale.set(1.05, 2.4, 1.05); });
    g.add(tube(Array.from({ length: 49 }, (_, i) => { const a = i / 48 * Math.PI * 2; const v = new THREE.Vector3(Math.cos(a) * 0.152, 0.012, Math.sin(a) * 0.152); v.applyAxisAngle(new THREE.Vector3(0, 0, 1), 0.62); v.y += 0.69; return v; }), INK, M.trim));
    for (let k = 0; k < 12; k++) { const a = k / 12 * Math.PI * 2; const b = sphere(0.011, 0.502, M.trim); b.position.x = Math.cos(a) * 0.138; b.position.z = Math.sin(a) * 0.138; g.add(b); }
  },
  queen(g, M) {
    meridians(g, M, 12, 0.13, 0.64); ring(g, M, 0.3); ring(g, M, 0.5);
    const pts = latheOf(g).geometry.parameters.points;
    for (let k = 0; k < 10; k++) { const a = (k + 0.5) / 10 * Math.PI * 2;
      const seg = []; for (let i = 0; i <= 12; i++) { const y = 0.69 + (0.87 - 0.69) * i / 12; const r = radiusAt(pts, y) + 0.003; seg.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
      g.add(tube(seg, INK * 0.8, M.ink)); }
    ring(g, M, 0.78); meridians(g, M, 10, 0.885, 0.95);
  },
  king(g, M) {
    meridians(g, M, 12, 0.13, 0.68); ring(g, M, 0.3); ring(g, M, 0.5);
    const pts = latheOf(g).geometry.parameters.points;
    for (let k = 0; k < 12; k++) { const a = (k + 0.5) / 12 * Math.PI * 2;
      const seg = []; for (let i = 0; i <= 12; i++) { const y = 0.735 + (0.905 - 0.735) * i / 12; const r = radiusAt(pts, y) + 0.003; seg.push([Math.sin(a) * r, y, Math.cos(a) * r]); }
      g.add(tube(seg, INK * 0.8, M.ink)); }
    ring(g, M, 0.82); meridians(g, M, 10, 0.928, 0.995);
  },
  knight(g, M, depth) {
    const Y = 0.16, zf = depth / 2 + 0.05 + 0.0015;
    // drop the bead mane and the old dot eyes; carve instead
    g.children.slice().forEach(o => { if (o.geometry && (o.geometry.type === 'SphereGeometry' || (o.geometry.type === 'TorusGeometry' && o.geometry.parameters.radius === 0.105))) g.remove(o); });
    // raised cheek, carved in relief
    for (const z of [-1, 1]) { const ch = sphere(0.075, 0, M.body); ch.scale.set(1.15, 0.95, 0.16); ch.position.set(0.125, Y + 0.425, z * (zf - 0.006)); g.add(ch); }
    meridians(g, M, 12, 0.02, 0.16);
    const side = (pts2, r = INK, mat = M.ink) => { for (const z of [-1, 1]) g.add(tube(pts2.map(([x, y]) => [x, y + Y, z * zf]), r, mat)); };
    const curve = (ctrl, n = 24) => new THREE.SplineCurve(ctrl.map(([x, y]) => new THREE.Vector2(x, y))).getPoints(n).map(v => [v.x, v.y]);
    // eye: almond socket, eyeball, iris and catchlight, with a brow
    for (const z of [-1, 1]) {
      const sock = sphere(0.04, 0, M.socket); sock.scale.set(1.3, 0.78, 0.3); sock.position.set(0.115, Y + 0.545, z * (zf - 0.004)); g.add(sock);
      const ball = sphere(0.026, 0, M.eye); ball.scale.set(1.1, 1.0, 0.5); ball.position.set(0.12, Y + 0.545, z * (zf + 0.002)); g.add(ball);
      const glint = sphere(0.0065, 0, new THREE.MeshBasicMaterial({ color: 0xffffff })); glint.position.set(0.13, Y + 0.555, z * (zf + 0.015)); g.add(glint);
    }
    side(curve([[0.07, 0.548], [0.1, 0.572], [0.14, 0.572], [0.17, 0.55]]), INK * 1.1);          // upper lid / brow
    side(curve([[0.08, 0.538], [0.115, 0.522], [0.155, 0.532]]), INK * 0.8);                       // lower lid
    side(curve([[0.065, 0.585], [0.11, 0.6], [0.165, 0.59], [0.2, 0.56]]), INK * 0.7);              // brow ridge
    // nostril and mouth
    for (const z of [-1, 1]) { const n = sphere(0.019, 0, M.socket); n.scale.set(1.2, 0.7, 0.3); n.position.set(0.262, Y + 0.375, z * (zf - 0.003)); n.rotation.z = -0.5; g.add(n); }
    side(curve([[0.238, 0.362], [0.262, 0.395], [0.288, 0.382]]), INK * 0.8);
    side(curve([[0.302, 0.322], [0.27, 0.318], [0.235, 0.322], [0.205, 0.335]]), INK);
    // cheek: the round jaw muscle of a Staunton knight
    side(curve([[0.205, 0.345], [0.16, 0.36], [0.1, 0.37], [0.06, 0.41], [0.065, 0.47], [0.1, 0.5], [0.15, 0.49]], 40), INK * 1.05);
    // nose ridge and face line
    side(curve([[0.08, 0.63], [0.15, 0.575], [0.22, 0.5], [0.27, 0.43]]), INK * 0.7);
    // ear: inner fold
    side(curve([[-0.035, 0.675], [-0.015, 0.735], [0.0, 0.73], [0.025, 0.675]]), INK * 0.9);
    // mane: carved locks along the neck, each a raised ridge with an inked edge
    const back = new THREE.CubicBezierCurve(new THREE.Vector2(-0.205, 0.04), new THREE.Vector2(-0.235, 0.2), new THREE.Vector2(-0.19, 0.4), new THREE.Vector2(-0.05, 0.66));
    const N = 11;
    for (let i = 0; i < N; i++) {
      const t = (i + 0.5) / N, p = back.getPoint(t), tg = back.getTangent(t);
      const nx = tg.y, ny = -tg.x;        // normal pointing into the neck
      const len = 0.07 + 0.03 * Math.sin(t * Math.PI);
      const lock = []; for (let j = 0; j <= 8; j++) { const u = j / 8; lock.push([p.x + nx * len * u + tg.x * 0.025 * Math.sin(u * Math.PI), p.y + ny * len * u + tg.y * 0.025 * Math.sin(u * Math.PI) + 0.012 * u]); }
      side(lock, INK * 0.85);
      // a raised lock in the body material on the crest
      const rib = sphere(0.03, 0, M.body); rib.scale.set(0.75, 1.5, 3.5);
      rib.position.set(p.x - nx * 0.008, p.y + Y - ny * 0.008, 0); rib.rotation.z = Math.atan2(tg.y, tg.x); g.add(rib);
    }
    // amber bridle kept, plus a brow band
    side(curve([[0.02, 0.665], [0.07, 0.635], [0.1, 0.62]]), INK * 1.6, M.trim);
  },
};

const MATS = TH.mats();
let KNIGHT_PROFILE = false;
const wireMat = new THREE.LineBasicMaterial({ color: 0xeaf2ff, transparent: true, opacity: 0.85 });
function addWire(g) {
  const meshes = []; g.traverse(o => { if (o.isMesh) meshes.push(o); });
  for (const m of meshes) {
    m.add(new THREE.LineSegments(new THREE.EdgesGeometry(m.geometry, 28), wireMat));
    const pts = m.geometry.parameters && m.geometry.parameters.points;
    if (pts && m.geometry.type === 'LatheGeometry') {
      for (let k = 0; k < 12; k++) {
        const a = k / 12 * Math.PI * 2;
        const line = pts.map(v => new THREE.Vector3(Math.sin(a) * v.x * 1.006, v.y, Math.cos(a) * v.x * 1.006));
        m.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(line), wireMat));
      }
    }
  }
}
function piece(type, side, x, z, rotY = 0) {
  const g = builders[type](MATS[side]);
  g.position.set(x, 0, z);
  if (TH.wire) DETAIL[type](g, MATS[side], P('kd', 0.12));
  if (type === 'knight') g.rotation.y = rotY + (KNIGHT_PROFILE ? Math.PI + P('kr', 0.3) : (side === 'w' ? P('kw', 2.25) : P('kb', -2.0)));
  else g.rotation.y = rotY;
  scene.add(g); return g;
}
const sq = s => [s.charCodeAt(0) - 97 - 3.5, 3.5 - (+s[1] - 1)];

// ---------------------------------------------------------------- lights
function lights(shadowSize = 4096) {
  const key = new THREE.DirectionalLight(TH.env.warm, P('key', 2.2));
  if (SHOT === 'sprites') key.position.set(-3, 12, 4); else key.position.set(-5, 11, 6);
  key.castShadow = true;
  key.shadow.mapSize.set(shadowSize, shadowSize);
  const sc = SHOT === 'sprites' ? 1.5 : 6; Object.assign(key.shadow.camera, { left: -sc, right: sc, top: sc, bottom: -sc, near: 1, far: 30 });
  key.shadow.radius = 6; key.shadow.bias = -0.0004; key.shadow.normalBias = 0.01;
  scene.add(key);
  const rim = new THREE.DirectionalLight(TH.env.cool, P('rim', 0.9)); rim.position.set(6, 5, -8); scene.add(rim);
}

// ---------------------------------------------------------------- shots
const FEN = Q.get('fen') || 'r2q1rk1/pp2bppp/2n1bn2/3p4/3P4/2NBBN2/PP3PPP/R2Q1RK1';
const TYPES = { p: 'pawn', r: 'rook', n: 'knight', b: 'bishop', q: 'queen', k: 'king' };
function setupFen(fen) {
  fen.split('/').forEach((row, ri) => { let f = 0; for (const ch of row) { if (/\d/.test(ch)) f += +ch; else { const side = ch === ch.toUpperCase() ? 'w' : 'b'; piece(TYPES[ch.toLowerCase()], side, f - 3.5, ri - 3.5); f++; } } });
}

async function main() {
  await document.fonts.load('500 40px "Cormorant Garamond"').catch(() => {});
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
    lights(2048);
    const catcher = new THREE.Mesh(new THREE.PlaneGeometry(6, 6), new THREE.ShadowMaterial({ opacity: P('so', 0.5) }));
    catcher.rotation.x = -Math.PI / 2; catcher.receiveShadow = true; scene.add(catcher);
    const el = P('el', 38) * Math.PI / 180;
    const bottom = P('sb', -0.42), top = P('st', 1.0), hw = P('hw', 0.65); // sprite units: 1 = one square width
    camera = new THREE.OrthographicCamera(-hw, hw, top, bottom, 0.1, 50);
    const dist = 10; camera.position.set(0, Math.sin(el) * dist, Math.cos(el) * dist); camera.lookAt(0, 0, 0);
    const out = [];
    for (const side of ['w', 'b']) for (const t of ['king', 'queen', 'rook', 'bishop', 'knight', 'pawn']) {
      const g = piece(t, side, 0, 0);
      renderer.render(scene, camera);
      out.push([side + ({ king: 'K', queen: 'Q', rook: 'R', bishop: 'B', knight: 'N', pawn: 'P' })[t], renderer.domElement.toDataURL('image/png')]);
      scene.remove(g);
    }
    window.__png = out; window.__done = true; return;
  }
  renderer.render(scene, camera);
  window.__done = true;
}
main();
