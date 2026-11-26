// Mochy Cloud — máy chủ tài khoản + đồng bộ thư viện (Cloudflare Workers + Durable Object SQLite).
// Mật khẩu chỉ lưu dạng băm PBKDF2 (có salt); không bao giờ lưu mật khẩu thật.
// Dữ liệu nằm trong SQLite của một Durable Object (gói miễn phí: 100.000 dòng ghi/ngày, thay cho KV chỉ có 1.000 lượt ghi/ngày).
// KV cũ (MOCHY_KV) chỉ còn dùng để đọc và tự chuyển dữ liệu/phiên đăng nhập cũ sang SQLite.

import { DurableObject } from "cloudflare:workers";

const JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, content-type',
  'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
};
// Huy hiệu do chủ app cấp (sửa danh sách này rồi đẩy lên GitHub là tự triển khai).
const BADGES = {
  pucpucpuc: ['verified', 'owner'],
  bonheocho: ['blue'],   // tick xanh: người giúp tìm ra rất nhiều lỗi
};
const LANG_NAMES = {
  vi: 'vietnamese', en: 'english', ja: 'japanese', ko: 'korean', 'zh-CN': 'chinese', th: 'thai',
  fr: 'french', es: 'spanish', id: 'indonesian', ru: 'russian'
};
const MAX_BLOB = 2 * 1024 * 1024;
const SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 365;
const ITERATIONS = 100000;

const reply = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: JSON_HEADERS });
const fail = (status, message) => reply({ error: message }, status);

const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
const fromHex = (s) => new Uint8Array(s.match(/../g).map((h) => parseInt(h, 16)));

async function hashPassword(password, saltHex, iterations = ITERATIONS) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: fromHex(saltHex), iterations }, key, 256);
  return hex(bits);
}

function sameString(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const validName = (name) => typeof name === 'string' && /^[a-z0-9_.-]{3,24}$/.test(name);
const validPassword = (pw) => typeof pw === 'string' && pw.length >= 6 && pw.length <= 128;

async function readJSON(request) {
  try { return await request.json(); } catch (e) { return null; }
}

export default {
  async fetch(request, env) {
    try {
      const stub = env.MOCHY_DO.get(env.MOCHY_DO.idFromName('main'));
      return await stub.fetch(request);
    } catch (e) {
      return fail(500, 'Lỗi máy chủ: ' + String((e && e.message) || e).slice(0, 160));
    }
  },
};

export class MochyDO extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.env = env;
    this.sql = ctx.storage.sql;
    this.hits = new Map();
    const s = this.sql;
    s.exec('CREATE TABLE IF NOT EXISTS users (name TEXT PRIMARY KEY, salt TEXT NOT NULL, hash TEXT NOT NULL, iterations INTEGER NOT NULL, created INTEGER NOT NULL)');
    s.exec('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, name TEXT NOT NULL, expires INTEGER NOT NULL)');
    s.exec('CREATE TABLE IF NOT EXISTS data (name TEXT PRIMARY KEY, version INTEGER NOT NULL, updated INTEGER NOT NULL, blob TEXT NOT NULL)');
    s.exec('CREATE TABLE IF NOT EXISTS avatars (name TEXT PRIMARY KEY, image TEXT NOT NULL)');
  }

  rows(query, ...params) { return this.sql.exec(query, ...params).toArray(); }
  one(query, ...params) { return this.rows(query, ...params)[0] || null; }
  run(query, ...params) { this.sql.exec(query, ...params); }

  // Giới hạn số lần theo khoá trong bộ nhớ (chỉ có một Durable Object nên đủ dùng, không tốn lượt ghi).
  allow(key, limit, seconds) {
    const now = Date.now();
    const e = this.hits.get(key);
    if (!e || now > e.reset) {
      this.hits.set(key, { n: 1, reset: now + seconds * 1000 });
      if (this.hits.size > 5000) this.hits.clear();
      return true;
    }
    e.n += 1;
    return e.n <= limit;
  }

  // --- Dữ liệu KV cũ: đọc và chuyển sang SQLite khi gặp ---
  async legacyUser(name) {
    try {
      const raw = await this.env.MOCHY_KV.get(`user:${name}`);
      return raw ? JSON.parse(raw) : null;
    } catch (e) { return null; }
  }

  async getUser(name) {
    const row = this.one('SELECT * FROM users WHERE name = ?', name);
    if (row) return row;
    const old = await this.legacyUser(name);
    if (!old) return null;
    this.run('INSERT OR IGNORE INTO users (name, salt, hash, iterations, created) VALUES (?, ?, ?, ?, ?)',
      name, old.salt, old.hash, old.iterations || ITERATIONS, old.created || Date.now());
    return this.one('SELECT * FROM users WHERE name = ?', name);
  }

  newSession(name) {
    const token = hex(crypto.getRandomValues(new Uint8Array(32)));
    this.run('INSERT INTO sessions (token, name, expires) VALUES (?, ?, ?)', token, name, Date.now() + SESSION_TTL_MS);
    return token;
  }

  async authed(request) {
    const header = request.headers.get('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
    if (!/^[0-9a-f]{64}$/.test(token)) return null;
    const row = this.one('SELECT name, expires FROM sessions WHERE token = ?', token);
    if (row) return row.expires > Date.now() ? { name: row.name, token } : null;
    try {
      const name = await this.env.MOCHY_KV.get(`sess:${token}`);
      if (name) {
        this.run('INSERT OR IGNORE INTO sessions (token, name, expires) VALUES (?, ?, ?)', token, name, Date.now() + SESSION_TTL_MS);
        return { name, token };
      }
    } catch (e) { /* bỏ qua */ }
    return null;
  }

  async userExists(name) {
    return !!(await this.getUser(name));
  }

  edgeNames(query, name) {
    return this.rows(query, name).map((r) => r.n);
  }

  async fetch(request) {
    try {
      return await this.handle(request);
    } catch (e) {
      return fail(500, 'Lỗi máy chủ: ' + String((e && e.message) || e).slice(0, 160));
    }
  }

  async handle(request) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: JSON_HEADERS });
    const url = new URL(request.url);
    const ip = request.headers.get('cf-connecting-ip') || 'unknown';
    const path = url.pathname.replace(/\/+$/, '') || '/';

    if (path === '/' && request.method === 'GET') return reply({ ok: true, service: 'mochy-cloud', storage: 'sqlite' });

    if (path === '/register' && request.method === 'POST') {
      const body = await readJSON(request);
      if (!body) return fail(400, 'Dữ liệu không hợp lệ');
      const name = String(body.username || '').trim().toLowerCase();
      if (!validName(name)) return fail(400, 'Tên đăng nhập 3–24 ký tự: chữ thường, số, _ . -');
      if (!validPassword(body.password)) return fail(400, 'Mật khẩu từ 6 đến 128 ký tự');
      if (!this.allow(`reg:${ip}`, 8, 3600)) return fail(429, 'Tạo tài khoản quá nhiều lần, thử lại sau');
      if (await this.userExists(name)) return fail(409, 'Tên đăng nhập đã có người dùng');
      const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
      const hash = await hashPassword(body.password, salt);
      this.run('INSERT INTO users (name, salt, hash, iterations, created) VALUES (?, ?, ?, ?, ?)', name, salt, hash, ITERATIONS, Date.now());
      return reply({ token: this.newSession(name), username: name });
    }

    if (path === '/login' && request.method === 'POST') {
      const body = await readJSON(request);
      if (!body) return fail(400, 'Dữ liệu không hợp lệ');
      const name = String(body.username || '').trim().toLowerCase();
      if (!validName(name) || typeof body.password !== 'string') return fail(401, 'Sai tên đăng nhập hoặc mật khẩu');
      if (!this.allow(`login:${name}:${ip}`, 10, 900)) return fail(429, 'Thử sai quá nhiều lần, đợi 15 phút');
      const user = await this.getUser(name);
      if (!user) return fail(401, 'Sai tên đăng nhập hoặc mật khẩu');
      const hash = await hashPassword(body.password, user.salt, user.iterations);
      if (!sameString(hash, user.hash)) return fail(401, 'Sai tên đăng nhập hoặc mật khẩu');
      return reply({ token: this.newSession(name), username: name });
    }

    const who = await this.authed(request);
    if (!who) return fail(401, 'Phiên đăng nhập hết hạn');

    if (path === '/logout' && request.method === 'POST') {
      this.run('DELETE FROM sessions WHERE token = ?', who.token);
      return reply({ ok: true });
    }

    if (path === '/password' && request.method === 'POST') {
      const body = await readJSON(request);
      if (!body || !validPassword(body.newPassword)) return fail(400, 'Mật khẩu mới từ 6 đến 128 ký tự');
      const user = await this.getUser(who.name);
      if (!user) return fail(404, 'Không tìm thấy tài khoản');
      if (!sameString(await hashPassword(String(body.oldPassword || ''), user.salt, user.iterations), user.hash)) return fail(401, 'Mật khẩu cũ không đúng');
      const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
      this.run('UPDATE users SET salt = ?, hash = ?, iterations = ? WHERE name = ?', salt, await hashPassword(body.newPassword, salt), ITERATIONS, who.name);
      return reply({ ok: true });
    }

    if (path === '/account' && request.method === 'DELETE') {
      this.run('DELETE FROM data WHERE name = ?', who.name);
      this.run('DELETE FROM avatars WHERE name = ?', who.name);
      this.run('DELETE FROM sessions WHERE name = ?', who.name);
      this.run('DELETE FROM users WHERE name = ?', who.name);
      try {
        await this.env.MOCHY_KV.delete(`user:${who.name}`);
        await this.env.MOCHY_KV.delete(`data:${who.name}`);
        await this.env.MOCHY_KV.delete(`avatar:${who.name}`);
      } catch (e) { /* KV hết lượt ghi thì bỏ qua */ }
      return reply({ ok: true });
    }

    if (path === '/profile' && request.method === 'GET') {
      return reply({ username: who.name, badges: BADGES[who.name] || [] });
    }

    if (path === '/avatar' && request.method === 'GET') {
      const target = (url.searchParams.get('user') || who.name).toLowerCase();
      if (!validName(target)) return fail(400, 'Tên không hợp lệ');
      let row = this.one('SELECT image FROM avatars WHERE name = ?', target);
      if (!row) {
        try {
          const old = await this.env.MOCHY_KV.get(`avatar:${target}`);
          if (old) {
            this.run('INSERT OR IGNORE INTO avatars (name, image) VALUES (?, ?)', target, old);
            row = { image: old };
          }
        } catch (e) { /* bỏ qua */ }
      }
      return reply({ image: row ? row.image : null });
    }

    if (path === '/avatar' && request.method === 'PUT') {
      const body = await readJSON(request);
      const image = body && body.image;
      // Chỉ nhận ảnh JPEG (base64) nhỏ; app tự thu nhỏ về 256px trước khi gửi.
      if (typeof image !== 'string' || image.length > 150000 || !image.startsWith('/9j/') || !/^[A-Za-z0-9+/=]+$/.test(image)) {
        return fail(400, 'Ảnh không hợp lệ hoặc quá lớn');
      }
      if (!this.allow(`avatar:${who.name}`, 20, 3600)) return fail(429, 'Đổi ảnh quá nhiều lần, thử lại sau');
      this.run('INSERT OR REPLACE INTO avatars (name, image) VALUES (?, ?)', who.name, image);
      return reply({ ok: true });
    }

    if (path === '/avatar' && request.method === 'DELETE') {
      this.run('DELETE FROM avatars WHERE name = ?', who.name);
      return reply({ ok: true });
    }

    // Dịch lời bằng Workers AI (m2m100). Cần đăng nhập, có giới hạn tốc độ.
    if (path === '/translate' && request.method === 'POST') {
      if (!this.env.AI) return fail(501, 'Máy chủ chưa bật dịch');
      const body = await readJSON(request);
      const lines = body && Array.isArray(body.lines) ? body.lines : null;
      if (!lines || lines.length === 0 || lines.length > 40) return fail(400, 'Dữ liệu không hợp lệ');
      if (!this.allow(`tr:${who.name}`, 400, 3600)) return fail(429, 'Dịch quá nhiều, thử lại sau');
      const target = LANG_NAMES[String(body.to || '')];
      if (!target) return fail(400, 'Ngôn ngữ không hỗ trợ');
      const source = LANG_NAMES[String(body.from || '')] || 'english';
      const out = await Promise.all(lines.map(async (line) => {
        const text = String(line || '').slice(0, 300);
        if (!text.trim()) return '';
        try {
          const r = await this.env.AI.run('@cf/meta/m2m100-1.2b', { text, source_lang: source, target_lang: target });
          return String((r && r.translated_text) || '');
        } catch (e) { return ''; }
      }));
      if (out.every((t) => !t)) return fail(502, 'Không dịch được');
      return reply({ lines: out });
    }

    if (path === '/data' && request.method === 'GET') {
      let row = this.one('SELECT version, updated, blob FROM data WHERE name = ?', who.name);
      if (!row) {
        try {
          const raw = await this.env.MOCHY_KV.get(`data:${who.name}`);
          if (raw) {
            const old = JSON.parse(raw);
            this.run('INSERT OR IGNORE INTO data (name, version, updated, blob) VALUES (?, ?, ?, ?)', who.name, old.version || 1, old.updatedAt || Date.now(), old.blob || '');
            row = this.one('SELECT version, updated, blob FROM data WHERE name = ?', who.name);
          }
        } catch (e) { /* bỏ qua */ }
      }
      if (!row) return reply({ version: 0, blob: null });
      return reply({ version: row.version, updatedAt: row.updated, blob: row.blob });
    }

    if (path === '/data' && request.method === 'PUT') {
      const text = await request.text();
      if (text.length > MAX_BLOB + 1024) return fail(413, 'Dữ liệu quá lớn');
      let body;
      try { body = JSON.parse(text); } catch (e) { return fail(400, 'Dữ liệu không hợp lệ'); }
      if (typeof body.blob !== 'string' || body.blob.length > MAX_BLOB) return fail(413, 'Dữ liệu quá lớn');
      if (!this.allow(`put:${who.name}`, 240, 3600)) return fail(429, 'Đồng bộ quá nhiều lần, thử lại sau');
      let current = this.one('SELECT version, blob FROM data WHERE name = ?', who.name);
      if (!current) {
        try {
          const raw = await this.env.MOCHY_KV.get(`data:${who.name}`);
          if (raw) { const old = JSON.parse(raw); current = { version: old.version || 0, blob: old.blob || null }; }
        } catch (e) { /* bỏ qua */ }
      }
      const version = current ? current.version : 0;
      if (Number(body.baseVersion) !== version) {
        return reply({ conflict: true, version, blob: current ? current.blob : null }, 409);
      }
      this.run('INSERT OR REPLACE INTO data (name, version, updated, blob) VALUES (?, ?, ?, ?)', who.name, version + 1, Date.now(), body.blob);
      return reply({ version: version + 1 });
    }

    return fail(404, 'Không tìm thấy');
  }
}
