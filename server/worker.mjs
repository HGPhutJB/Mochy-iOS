// Mochy Cloud — máy chủ tài khoản + đồng bộ thư viện (Cloudflare Workers + KV).
// Mật khẩu chỉ lưu dạng băm PBKDF2 (có salt); không bao giờ lưu mật khẩu thật.

const JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, content-type',
  'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
};
// Huy hiệu do chủ app cấp (sửa danh sách này rồi đẩy lên GitHub là tự triển khai).
const BADGES = {
  pucpucpuc: ['verified', 'owner'],
};
const MAX_BLOB = 2 * 1024 * 1024;
const SESSION_TTL = 60 * 60 * 24 * 365;
const ITERATIONS = 100000;

const reply = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: JSON_HEADERS });
const fail = (status, message) => reply({ error: message }, status);

const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
const fromHex = (s) => new Uint8Array(s.match(/../g).map((h) => parseInt(h, 16)));

async function hashPassword(password, saltHex) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: fromHex(saltHex), iterations: ITERATIONS }, key, 256);
  return hex(bits);
}

function sameString(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function validName(name) {
  return typeof name === 'string' && /^[a-z0-9_.-]{3,24}$/.test(name);
}

function validPassword(pw) {
  return typeof pw === 'string' && pw.length >= 6 && pw.length <= 128;
}

// Giới hạn số lần theo khoá (IP...) trong một khoảng thời gian.
async function throttle(env, key, limit, seconds) {
  const k = `rl:${key}`;
  const n = parseInt((await env.MOCHY_KV.get(k)) || '0', 10);
  if (n >= limit) return false;
  await env.MOCHY_KV.put(k, String(n + 1), { expirationTtl: Math.max(60, seconds) });
  return true;
}

// Danh sách tên ở cuối các khoá có cùng tiền tố (cạnh theo dõi), tối đa 1000.
async function edgeSet(env, prefix) {
  const out = new Set();
  const list = await env.MOCHY_KV.list({ prefix, limit: 1000 });
  for (const k of list.keys) out.add(k.name.slice(prefix.length));
  return out;
}

async function newSession(env, name) {
  const token = hex(crypto.getRandomValues(new Uint8Array(32)));
  await env.MOCHY_KV.put(`sess:${token}`, name, { expirationTtl: SESSION_TTL });
  return token;
}

async function authed(request, env) {
  const header = request.headers.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!/^[0-9a-f]{64}$/.test(token)) return null;
  const name = await env.MOCHY_KV.get(`sess:${token}`);
  return name ? { name, token } : null;
}

async function readJSON(request) {
  try { return await request.json(); } catch (e) { return null; }
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: JSON_HEADERS });
    const url = new URL(request.url);
    const ip = request.headers.get('cf-connecting-ip') || 'unknown';
    const path = url.pathname.replace(/\/+$/, '') || '/';

    if (path === '/' && request.method === 'GET') return reply({ ok: true, service: 'mochy-cloud' });

    if (path === '/register' && request.method === 'POST') {
      const body = await readJSON(request);
      if (!body) return fail(400, 'Dữ liệu không hợp lệ');
      const name = String(body.username || '').trim().toLowerCase();
      if (!validName(name)) return fail(400, 'Tên đăng nhập 3–24 ký tự: chữ thường, số, _ . -');
      if (!validPassword(body.password)) return fail(400, 'Mật khẩu từ 6 đến 128 ký tự');
      if (!(await throttle(env, `reg:${ip}`, 8, 3600))) return fail(429, 'Tạo tài khoản quá nhiều lần, thử lại sau');
      if (await env.MOCHY_KV.get(`user:${name}`)) return fail(409, 'Tên đăng nhập đã có người dùng');
      const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
      const hash = await hashPassword(body.password, salt);
      await env.MOCHY_KV.put(`user:${name}`, JSON.stringify({ salt, hash, iterations: ITERATIONS, created: Date.now() }));
      return reply({ token: await newSession(env, name), username: name });
    }

    if (path === '/login' && request.method === 'POST') {
      const body = await readJSON(request);
      if (!body) return fail(400, 'Dữ liệu không hợp lệ');
      const name = String(body.username || '').trim().toLowerCase();
      if (!validName(name) || typeof body.password !== 'string') return fail(401, 'Sai tên đăng nhập hoặc mật khẩu');
      if (!(await throttle(env, `login:${name}:${ip}`, 10, 900))) return fail(429, 'Thử sai quá nhiều lần, đợi 15 phút');
      const raw = await env.MOCHY_KV.get(`user:${name}`);
      if (!raw) return fail(401, 'Sai tên đăng nhập hoặc mật khẩu');
      const user = JSON.parse(raw);
      const hash = await hashPassword(body.password, user.salt);
      if (!sameString(hash, user.hash)) return fail(401, 'Sai tên đăng nhập hoặc mật khẩu');
      return reply({ token: await newSession(env, name), username: name });
    }

    const who = await authed(request, env);
    if (!who) return fail(401, 'Phiên đăng nhập hết hạn');

    if (path === '/logout' && request.method === 'POST') {
      await env.MOCHY_KV.delete(`sess:${who.token}`);
      return reply({ ok: true });
    }

    if (path === '/password' && request.method === 'POST') {
      const body = await readJSON(request);
      if (!body || !validPassword(body.newPassword)) return fail(400, 'Mật khẩu mới từ 6 đến 128 ký tự');
      const raw = await env.MOCHY_KV.get(`user:${who.name}`);
      if (!raw) return fail(404, 'Không tìm thấy tài khoản');
      const user = JSON.parse(raw);
      if (!sameString(await hashPassword(String(body.oldPassword || ''), user.salt), user.hash)) return fail(401, 'Mật khẩu cũ không đúng');
      const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
      user.salt = salt;
      user.hash = await hashPassword(body.newPassword, salt);
      await env.MOCHY_KV.put(`user:${who.name}`, JSON.stringify(user));
      return reply({ ok: true });
    }

    if (path === '/account' && request.method === 'DELETE') {
      for (const other of await edgeSet(env, `f:${who.name}:`)) {
        await env.MOCHY_KV.delete(`f:${who.name}:${other}`);
        await env.MOCHY_KV.delete(`r:${other}:${who.name}`);
      }
      for (const other of await edgeSet(env, `r:${who.name}:`)) {
        await env.MOCHY_KV.delete(`r:${who.name}:${other}`);
        await env.MOCHY_KV.delete(`f:${other}:${who.name}`);
      }
      await env.MOCHY_KV.delete(`user:${who.name}`);
      await env.MOCHY_KV.delete(`data:${who.name}`);
      await env.MOCHY_KV.delete(`avatar:${who.name}`);
      await env.MOCHY_KV.delete(`sess:${who.token}`);
      return reply({ ok: true });
    }

    if (path === '/profile' && request.method === 'GET') {
      return reply({ username: who.name, badges: BADGES[who.name] || [] });
    }

    if (path === '/avatar' && request.method === 'GET') {
      const target = (url.searchParams.get('user') || who.name).toLowerCase();
      if (!validName(target)) return fail(400, 'Tên không hợp lệ');
      const image = await env.MOCHY_KV.get(`avatar:${target}`);
      return reply({ image: image || null });
    }

    // Tìm người dùng theo tiền tố tên. Tài khoản có huy hiệu (chủ app...) khớp tiền tố luôn được ghim lên đầu.
    if (path === '/users/search' && request.method === 'GET') {
      const q = (url.searchParams.get('q') || '').trim().toLowerCase();
      if (!/^[a-z0-9_.-]{1,24}$/.test(q)) return reply({ users: [] });
      if (!(await throttle(env, `search:${who.name}`, 600, 3600))) return fail(429, 'Tìm quá nhiều, thử lại sau');
      const mine = await edgeSet(env, `f:${who.name}:`);
      const names = [];
      for (const featured of Object.keys(BADGES)) {
        if (featured.startsWith(q) && featured !== who.name && (await env.MOCHY_KV.get(`user:${featured}`))) names.push(featured);
      }
      const found = await env.MOCHY_KV.list({ prefix: `user:${q}`, limit: 20 });
      for (const k of found.keys) {
        const name = k.name.slice(5);
        if (name !== who.name && !names.includes(name)) names.push(name);
      }
      return reply({ users: names.slice(0, 20).map((n) => ({ username: n, badges: BADGES[n] || [], following: mine.has(n) })) });
    }

    if (path === '/follow' && request.method === 'POST') {
      const body = await readJSON(request);
      const target = String((body && body.username) || '').trim().toLowerCase();
      if (!validName(target) || target === who.name) return fail(400, 'Không thể theo dõi tài khoản này');
      if (!(await env.MOCHY_KV.get(`user:${target}`))) return fail(404, 'Không tìm thấy người dùng');
      if (!(await throttle(env, `follow:${who.name}`, 200, 3600))) return fail(429, 'Thao tác quá nhiều, thử lại sau');
      await env.MOCHY_KV.put(`f:${who.name}:${target}`, String(Date.now()));
      await env.MOCHY_KV.put(`r:${target}:${who.name}`, String(Date.now()));
      return reply({ ok: true });
    }

    if (path === '/follow' && request.method === 'DELETE') {
      const target = (url.searchParams.get('username') || '').trim().toLowerCase();
      if (!validName(target)) return fail(400, 'Tên không hợp lệ');
      await env.MOCHY_KV.delete(`f:${who.name}:${target}`);
      await env.MOCHY_KV.delete(`r:${target}:${who.name}`);
      return reply({ ok: true });
    }

    if (path === '/follows' && request.method === 'GET') {
      const following = [...(await edgeSet(env, `f:${who.name}:`))];
      const followers = [...(await edgeSet(env, `r:${who.name}:`))];
      const mine = new Set(following);
      const info = (n) => ({ username: n, badges: BADGES[n] || [], following: mine.has(n) });
      return reply({ following: following.map(info), followers: followers.map(info) });
    }

    if (path === '/avatar' && request.method === 'PUT') {
      const body = await readJSON(request);
      const image = body && body.image;
      // Chỉ nhận ảnh JPEG (base64) nhỏ; app tự thu nhỏ về 256px trước khi gửi.
      if (typeof image !== 'string' || image.length > 150000 || !image.startsWith('/9j/') || !/^[A-Za-z0-9+/=]+$/.test(image)) {
        return fail(400, 'Ảnh không hợp lệ hoặc quá lớn');
      }
      if (!(await throttle(env, `avatar:${who.name}`, 20, 3600))) return fail(429, 'Đổi ảnh quá nhiều lần, thử lại sau');
      await env.MOCHY_KV.put(`avatar:${who.name}`, image);
      return reply({ ok: true });
    }

    if (path === '/avatar' && request.method === 'DELETE') {
      await env.MOCHY_KV.delete(`avatar:${who.name}`);
      return reply({ ok: true });
    }

    if (path === '/data' && request.method === 'GET') {
      const raw = await env.MOCHY_KV.get(`data:${who.name}`);
      if (!raw) return reply({ version: 0, blob: null });
      return new Response(raw, { status: 200, headers: JSON_HEADERS });
    }

    if (path === '/data' && request.method === 'PUT') {
      const text = await request.text();
      if (text.length > MAX_BLOB + 1024) return fail(413, 'Dữ liệu quá lớn');
      let body;
      try { body = JSON.parse(text); } catch (e) { return fail(400, 'Dữ liệu không hợp lệ'); }
      if (typeof body.blob !== 'string' || body.blob.length > MAX_BLOB) return fail(413, 'Dữ liệu quá lớn');
      if (!(await throttle(env, `put:${who.name}`, 240, 3600))) return fail(429, 'Đồng bộ quá nhiều lần, thử lại sau');
      const raw = await env.MOCHY_KV.get(`data:${who.name}`);
      const current = raw ? JSON.parse(raw) : { version: 0, blob: null };
      if (Number(body.baseVersion) !== current.version) {
        return reply({ conflict: true, version: current.version, blob: current.blob }, 409);
      }
      const next = { version: current.version + 1, updatedAt: Date.now(), blob: body.blob };
      await env.MOCHY_KV.put(`data:${who.name}`, JSON.stringify(next));
      return reply({ version: next.version });
    }

    return fail(404, 'Không tìm thấy');
  },
};
