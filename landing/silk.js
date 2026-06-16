const canvas = document.getElementById("silk-canvas");
const gl = canvas.getContext("webgl", { antialias: true, alpha: false, powerPreference: "high-performance" });

const config = {
  color: "#3e3b48",
  speed: 5.0,
  scale: 1.0,
  rotation: -0.22,
  noiseIntensity: 1.75
};

const vertexShader = `
attribute vec2 aPosition;
varying vec2 vUv;

void main() {
  vUv = aPosition * 0.5 + 0.5;
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
`;

const fragmentShader = `
precision highp float;

varying vec2 vUv;

uniform float uTime;
uniform vec3 uColor;
uniform float uSpeed;
uniform float uScale;
uniform float uRotation;
uniform float uNoiseIntensity;
uniform vec2 uResolution;

const float e = 2.71828182845904523536;

float noise(vec2 texCoord) {
  float G = e;
  vec2 r = G * sin(G * texCoord);
  return fract(r.x * r.y * (1.0 + texCoord.x));
}

vec2 rotateUvs(vec2 uv, float angle) {
  float c = cos(angle);
  float s = sin(angle);
  mat2 rot = mat2(c, -s, s, c);
  return rot * uv;
}

void main() {
  vec2 fragCoord = gl_FragCoord.xy;
  float rnd = noise(fragCoord);
  vec2 correctedUv = vUv;
  correctedUv.x *= uResolution.x / max(uResolution.y, 1.0);
  correctedUv.x -= (uResolution.x / max(uResolution.y, 1.0) - 1.0) * 0.5;

  vec2 uv = rotateUvs(correctedUv * uScale, uRotation);
  vec2 tex = uv * uScale;
  float tOffset = uSpeed * uTime;

  tex.y += 0.03 * sin(8.0 * tex.x - tOffset);

  float pattern = 0.6 +
    0.4 * sin(5.0 * (tex.x + tex.y +
      cos(3.0 * tex.x + 5.0 * tex.y) +
      0.02 * tOffset) +
      sin(20.0 * (tex.x + tex.y - 0.1 * tOffset)));

  vec3 color = uColor * pattern - vec3(rnd / 15.0 * uNoiseIntensity);
  color += vec3(0.05, 0.045, 0.075) * smoothstep(0.25, 1.0, pattern);
  color += vec3(0.02, 0.055, 0.035) * smoothstep(0.8, 1.0, vUv.y);
  gl_FragColor = vec4(color, 1.0);
}
`;

function compileShader(type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);

  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(shader) || "Shader compile failed");
  }

  return shader;
}

function hexToRgb(hex) {
  const value = hex.replace("#", "");
  return [
    parseInt(value.slice(0, 2), 16) / 255,
    parseInt(value.slice(2, 4), 16) / 255,
    parseInt(value.slice(4, 6), 16) / 255
  ];
}

function createProgram() {
  const program = gl.createProgram();
  gl.attachShader(program, compileShader(gl.VERTEX_SHADER, vertexShader));
  gl.attachShader(program, compileShader(gl.FRAGMENT_SHADER, fragmentShader));
  gl.linkProgram(program);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error(gl.getProgramInfoLog(program) || "Program link failed");
  }

  return program;
}

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const width = Math.floor(canvas.clientWidth * dpr);
  const height = Math.floor(canvas.clientHeight * dpr);

  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
    gl.viewport(0, 0, width, height);
  }
}

if (!gl) {
  document.documentElement.classList.add("no-webgl");
} else {
  const program = createProgram();
  const vertices = new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]);
  const buffer = gl.createBuffer();

  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
  gl.useProgram(program);

  const positionLocation = gl.getAttribLocation(program, "aPosition");
  gl.enableVertexAttribArray(positionLocation);
  gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

  const uniforms = {
    time: gl.getUniformLocation(program, "uTime"),
    color: gl.getUniformLocation(program, "uColor"),
    speed: gl.getUniformLocation(program, "uSpeed"),
    scale: gl.getUniformLocation(program, "uScale"),
    rotation: gl.getUniformLocation(program, "uRotation"),
    noiseIntensity: gl.getUniformLocation(program, "uNoiseIntensity"),
    resolution: gl.getUniformLocation(program, "uResolution")
  };

  const rgb = hexToRgb(config.color);
  let last = performance.now();
  let elapsed = 0;

  function render(now) {
    resize();
    const delta = (now - last) / 1000;
    last = now;
    elapsed += delta * 0.1;

    gl.uniform1f(uniforms.time, elapsed);
    gl.uniform3f(uniforms.color, rgb[0], rgb[1], rgb[2]);
    gl.uniform1f(uniforms.speed, config.speed);
    gl.uniform1f(uniforms.scale, config.scale);
    gl.uniform1f(uniforms.rotation, config.rotation);
    gl.uniform1f(uniforms.noiseIntensity, config.noiseIntensity);
    gl.uniform2f(uniforms.resolution, canvas.width, canvas.height);
    gl.drawArrays(gl.TRIANGLES, 0, 6);

    requestAnimationFrame(render);
  }

  requestAnimationFrame(render);
}
