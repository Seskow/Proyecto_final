#!/bin/bash

# ─────────────────────────────────────────────
#  Hugo's Solutions — Instalador todo en uno
#  Ubuntu / Debian — v4.0
# ─────────────────────────────────────────────

RESET="\e[0m"; BOLD="\e[1m"; BLUE="\e[34m"; CYAN="\e[36m"
GREEN="\e[32m"; RED="\e[31m"; WHITE="\e[97m"; YELLOW="\e[33m"
PROJECT_DIR="/var/www/hugos-solutions"

clear
echo -e "${BLUE}${BOLD}"
cat << 'EOF'
  _   _                    _       
 | | | |_   _  __ _  ___ ( )___   
 | |_| | | | |/ _` |/ _ \|// __| 
 |  _  | |_| | (_| | (_) | \__ \ 
 |_| |_|\__,_|\__, |\___/  |___/ 
               |___/               
  ____        _       _   _                 
 / ___|  ___ | |_   _| |_(_) ___  _ __  ___ 
 \___ \ / _ \| | | | | __| |/ _ \| '_ \/ __|
  ___) | (_) | | |_| | |_| | (_) | | | \__ \
 |____/ \___/|_|\__,_|\__|_|\___/|_| |_|___/
EOF
echo -e "${CYAN}     ✦ Instalador Todo-en-Uno v4.0 ✦${RESET}"
echo -e "${WHITE}   Estepona · Málaga · España${RESET}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
sleep 1

spinner() {
    local pid=$1 msg=$2
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r  ${BLUE}${frames[$i]}${RESET}  ${WHITE}${msg}${RESET}   "
        i=$(( (i+1) % ${#frames[@]} )); sleep 0.08
    done
    printf "\r  ${GREEN}✔${RESET}  ${WHITE}${msg}${RESET}\n"
}
step() { echo -e "\n${CYAN}▶  $1${RESET}"; }
ok()   { echo -e "  ${GREEN}✔  $1${RESET}"; }

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}  ✘  Ejecuta como root: sudo bash install.sh${RESET}\n"; exit 1
fi

echo -e "${WHITE}  Iniciando instalación completa...${RESET}\n"; sleep 0.5

step "Actualizando sistema..."
(apt-get update -y > /dev/null 2>&1) & spinner $! "apt update"

step "Instalando dependencias base..."
(apt-get install -y curl git build-essential ca-certificates gnupg > /dev/null 2>&1) & spinner $! "herramientas base"

step "Instalando Node.js LTS..."
if ! command -v node &> /dev/null; then
    (curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - > /dev/null 2>&1 \
     && apt-get install -y nodejs > /dev/null 2>&1) & spinner $! "Node.js"
    ok "Node.js $(node -v)"
else
    ok "Node.js ya instalado ($(node -v))"
fi

step "Instalando Nginx..."
(apt-get install -y nginx > /dev/null 2>&1) & spinner $! "Nginx"

step "Creando estructura..."
mkdir -p "$PROJECT_DIR"/public
cd "$PROJECT_DIR"

cat > package.json << 'PKGJSON'
{
  "name": "hugos-solutions",
  "version": "4.0.0",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "author": "Hugo",
  "license": "ISC"
}
PKGJSON

step "Instalando dependencias Node.js..."
(npm install express better-sqlite3 bcryptjs express-session socket.io > /dev/null 2>&1) & spinner $! "express, sqlite3, bcryptjs, session, socket.io"
ok "Dependencias listas"

# ══════════════════════════════════════════════
step "Generando server.js..."
cat > "$PROJECT_DIR/server.js" << 'SERVERJS'
const express   = require('express');
const session   = require('express-session');
const bcrypt    = require('bcryptjs');
const Database  = require('better-sqlite3');
const path      = require('path');
const http      = require('http');
const { Server } = require('socket.io');

const app    = express();
const server = http.createServer(app);
const io     = new Server(server);
const PORT   = 3000;
const db     = new Database(path.join(__dirname, 'hugos.db'));

// ── DB INIT ─────────────────────────────────
db.exec(`
  CREATE TABLE IF NOT EXISTS employees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    role TEXT DEFAULT 'employee'
  );
  CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT, email TEXT, service TEXT, message TEXT,
    status TEXT DEFAULT 'unread',
    created_at TEXT DEFAULT (datetime('now','localtime'))
  );
  CREATE TABLE IF NOT EXISTS chat_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    client_name TEXT, client_email TEXT,
    cart TEXT DEFAULT '[]',
    status TEXT DEFAULT 'open',
    created_at TEXT DEFAULT (datetime('now','localtime'))
  );
  CREATE TABLE IF NOT EXISTS chat_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER, sender TEXT, sender_name TEXT,
    message TEXT,
    created_at TEXT DEFAULT (datetime('now','localtime')),
    FOREIGN KEY(session_id) REFERENCES chat_sessions(id)
  );
`);

// Seed admin
if (!db.prepare("SELECT id FROM employees WHERE email=?").get("admin@hugos.com")) {
  db.prepare("INSERT INTO employees (name,email,password,role) VALUES (?,?,?,?)").run("Hugo","admin@hugos.com",bcrypt.hashSync("admin1234",10),"admin");
  db.prepare("INSERT INTO employees (name,email,password,role) VALUES (?,?,?,?)").run("Ana García","ana@hugos.com",bcrypt.hashSync("empleado1234",10),"employee");
}

// Seed messages
if (!db.prepare("SELECT COUNT(*) as c FROM messages").get().c) {
  [["Carlos López","carlos@empresa.es","Alquiler de Hosting","Necesito info sobre el plan profesional.","unread"],
   ["María Torres","maria@gmail.com","Reparaciones Informáticas","Mi portátil no arranca.","read"],
   ["Pedro Ruiz","pedro@tienda.com","Protección Anti-DDoS","Sufrimos un ataque el mes pasado.","unread"]
  ].forEach(m => db.prepare("INSERT INTO messages (name,email,service,message,status) VALUES (?,?,?,?,?)").run(...m));
}

// ── MIDDLEWARE ──────────────────────────────
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
const sessionMiddleware = session({
  secret: 'hugos-secret-2025', resave: false, saveUninitialized: false,
  cookie: { maxAge: 8*60*60*1000 }
});
app.use(sessionMiddleware);
app.use(express.static(path.join(__dirname, 'public')));

const auth = (req,res,next) => req.session.user ? next() : res.status(401).json({error:'No autenticado'});
const adminOnly = (req,res,next) => req.session.user?.role==='admin' ? next() : res.status(403).json({error:'Sin permisos'});

// Share session with socket.io
io.use((socket, next) => sessionMiddleware(socket.request, {}, next));

// ── AUTH ────────────────────────────────────
app.post('/api/login', (req,res) => {
  const u = db.prepare("SELECT * FROM employees WHERE email=?").get(req.body.email);
  if (!u || !bcrypt.compareSync(req.body.password, u.password)) return res.status(401).json({error:'Credenciales incorrectas'});
  req.session.user = {id:u.id, name:u.name, email:u.email, role:u.role};
  res.json({ok:true, user:req.session.user});
});
app.post('/api/logout', (req,res) => { req.session.destroy(); res.json({ok:true}); });
app.get('/api/me', auth, (req,res) => res.json(req.session.user));

// ── MENSAJES FORMULARIO ──────────────────────
app.post('/api/contact', (req,res) => {
  const {name,email,service,message} = req.body;
  if (!name||!email||!message) return res.status(400).json({error:'Faltan campos'});
  db.prepare("INSERT INTO messages (name,email,service,message) VALUES (?,?,?,?)").run(name,email,service,message);
  res.json({ok:true});
});
app.get('/api/messages', auth, (req,res) => res.json(db.prepare("SELECT * FROM messages ORDER BY created_at DESC").all()));
app.patch('/api/messages/:id/status', auth, (req,res) => {
  db.prepare("UPDATE messages SET status=? WHERE id=?").run(req.body.status, req.params.id);
  res.json({ok:true});
});
app.delete('/api/messages/:id', auth, (req,res) => {
  db.prepare("DELETE FROM messages WHERE id=?").run(req.params.id);
  res.json({ok:true});
});

// ── STATS ───────────────────────────────────
app.get('/api/stats', auth, (req,res) => {
  const total    = db.prepare("SELECT COUNT(*) as c FROM messages").get().c;
  const unread   = db.prepare("SELECT COUNT(*) as c FROM messages WHERE status='unread'").get().c;
  const byService= db.prepare("SELECT service, COUNT(*) as c FROM messages GROUP BY service ORDER BY c DESC").all();
  const openChats= db.prepare("SELECT COUNT(*) as c FROM chat_sessions WHERE status='open'").get().c;
  res.json({total, unread, read:total-unread, byService, openChats});
});

// ── EMPLEADOS ───────────────────────────────
app.get('/api/employees', auth, (req,res) => res.json(db.prepare("SELECT id,name,email,role FROM employees").all()));
app.post('/api/employees', auth, adminOnly, (req,res) => {
  const {name,email,password,role} = req.body;
  try {
    db.prepare("INSERT INTO employees (name,email,password,role) VALUES (?,?,?,?)").run(name,email,bcrypt.hashSync(password,10),role||'employee');
    res.json({ok:true});
  } catch(e) { res.status(400).json({error:'Email ya existe'}); }
});
app.delete('/api/employees/:id', auth, adminOnly, (req,res) => {
  db.prepare("DELETE FROM employees WHERE id=?").run(req.params.id);
  res.json({ok:true});
});
app.patch('/api/employees/:id/password', auth, (req,res) => {
  const {currentPassword, newPassword} = req.body;
  const u = db.prepare("SELECT * FROM employees WHERE id=?").get(req.params.id);
  if (!u) return res.status(404).json({error:'No encontrado'});
  // admin puede cambiar cualquiera, empleado solo la suya con contraseña actual
  if (req.session.user.role !== 'admin') {
    if (req.session.user.id !== u.id) return res.status(403).json({error:'Sin permisos'});
    if (!bcrypt.compareSync(currentPassword, u.password)) return res.status(401).json({error:'Contraseña actual incorrecta'});
  }
  db.prepare("UPDATE employees SET password=? WHERE id=?").run(bcrypt.hashSync(newPassword,10), u.id);
  res.json({ok:true});
});

// ── CHAT SESSIONS ───────────────────────────
app.get('/api/chats', auth, (req,res) => {
  const sessions = db.prepare("SELECT * FROM chat_sessions ORDER BY created_at DESC").all();
  res.json(sessions);
});
app.get('/api/chats/:id/messages', auth, (req,res) => {
  res.json(db.prepare("SELECT * FROM chat_messages WHERE session_id=? ORDER BY created_at ASC").all(req.params.id));
});
app.patch('/api/chats/:id/close', auth, (req,res) => {
  db.prepare("UPDATE chat_sessions SET status='closed' WHERE id=?").run(req.params.id);
  io.to('session_'+req.params.id).emit('chat_closed');
  res.json({ok:true});
});

// ── SOCKET.IO ───────────────────────────────
const activeSockets = {}; // sessionId -> [socketIds]

io.on('connection', (socket) => {
  const user = socket.request.session?.user;

  // Cliente público inicia chat
  socket.on('client_start', ({name, email, cart}) => {
    const sess = db.prepare("INSERT INTO chat_sessions (client_name,client_email,cart) VALUES (?,?,?)").run(name, email, JSON.stringify(cart));
    const sessionId = sess.lastInsertRowid;
    socket.join('session_'+sessionId);
    socket.sessionId = sessionId;
    socket.clientName = name;
    socket.clientEmail = email;
    socket.emit('chat_started', {sessionId});
    // Notificar a todos los empleados conectados
    io.to('employees').emit('new_chat', {
      id: sessionId, client_name: name, client_email: email,
      cart: JSON.stringify(cart), status:'open',
      created_at: new Date().toLocaleString('es-ES')
    });
  });

  // Empleado/admin se une a sala de empleados
  socket.on('employee_join', () => {
    if (!user) return;
    socket.join('employees');
    socket.employeeId = user.id;
    socket.employeeName = user.name;
  });

  // Empleado entra a un chat específico
  socket.on('join_session', (sessionId) => {
    if (!user) return;
    socket.join('session_'+sessionId);
    socket.currentSession = sessionId;
  });

  // Mensaje enviado
  socket.on('send_message', ({sessionId, message}) => {
    if (!message.trim()) return;
    const isEmployee = !!user;
    const sender = isEmployee ? 'employee' : 'client';
    const senderName = isEmployee ? user.name : socket.clientName;
    db.prepare("INSERT INTO chat_messages (session_id,sender,sender_name,message) VALUES (?,?,?,?)").run(sessionId, sender, senderName, message);
    const msg = { sender, sender_name: senderName, message, created_at: new Date().toLocaleString('es-ES') };
    io.to('session_'+sessionId).emit('new_message', msg);
    // Notificar badge a empleados
    if (!isEmployee) io.to('employees').emit('chat_activity', {sessionId});
  });

  socket.on('disconnect', () => {});
});

// ── RUTAS HTML ──────────────────────────────
app.get('/',       (req,res) => res.sendFile(path.join(__dirname,'public','index.html')));
app.get('/login',  (req,res) => res.sendFile(path.join(__dirname,'public','login.html')));
app.get('/panel',  (req,res) => res.sendFile(path.join(__dirname,'public','panel.html')));

server.listen(PORT, () => console.log(`\n  ✔  Hugo's Solutions → http://localhost:${PORT}\n`));
SERVERJS
ok "server.js generado"

# ══════════════════════════════════════════════
step "Generando index.html (web pública con carrito y chat)..."
cat > "$PROJECT_DIR/public/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Hugo's Solutions</title>
<script src="/socket.io/socket.io.js"></script>
<style>
:root{--bg:#1a1208;--bg2:#221808;--card:#2a1f0e;--accent:#d4721a;--light:#f0a050;--text:#f5dfc0;--muted:#c4a07a;--white:#fff8f0;--border:rgba(240,160,80,0.15);--green:#7ac840}
*{margin:0;padding:0;box-sizing:border-box}html{scroll-behavior:smooth}
body{background:var(--bg);color:var(--text);font-family:'Segoe UI',Arial,sans-serif}
nav{position:fixed;top:0;width:100%;z-index:200;background:rgba(26,18,8,0.95);backdrop-filter:blur(12px);border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;padding:0 2.5rem;height:64px}
.nav-logo{display:flex;align-items:center;gap:.7rem}
.logo-icon{width:38px;height:38px;border-radius:8px;background:linear-gradient(135deg,var(--accent),var(--light));display:flex;align-items:center;justify-content:center;font-size:1.3rem;font-weight:900;color:#fff}
.nav-logo span{font-size:1.1rem;font-weight:700;color:var(--white)}
.nav-logo small{color:var(--muted);font-size:.72rem;display:block}
nav ul{list-style:none;display:flex;gap:1.5rem}
nav ul a{color:var(--muted);text-decoration:none;font-size:.85rem;transition:.2s}
nav ul a:hover{color:var(--light)}
.nav-right{display:flex;align-items:center;gap:.5rem}
.nav-emp{background:transparent;color:var(--muted);border:1px solid var(--border);padding:.4rem .9rem;border-radius:6px;cursor:pointer;font-size:.8rem;text-decoration:none;transition:.2s}
.nav-emp:hover{color:var(--light);border-color:var(--light)}
.cart-btn{position:relative;background:var(--accent);color:#fff;border:none;padding:.45rem 1rem;border-radius:6px;cursor:pointer;font-size:.88rem;font-weight:600;transition:.2s;display:flex;align-items:center;gap:.4rem}
.cart-btn:hover{background:var(--light);color:var(--bg)}
.cart-count{background:#c0392b;color:#fff;font-size:.65rem;font-weight:800;min-width:18px;height:18px;border-radius:9px;display:flex;align-items:center;justify-content:center;padding:0 4px}
/* HERO */
.hero{min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:6rem 2rem 4rem;background:radial-gradient(ellipse 80% 60% at 50% 30%,rgba(212,114,26,0.15) 0%,transparent 70%),linear-gradient(180deg,#1a1208,#120d04)}
.badge{display:inline-flex;align-items:center;gap:.5rem;background:rgba(240,160,80,0.12);border:1px solid rgba(240,160,80,0.3);color:var(--light);padding:.35rem 1rem;border-radius:20px;font-size:.78rem;font-weight:600;margin-bottom:1.5rem}
.hero h1{font-size:clamp(2.4rem,5vw,4rem);font-weight:800;color:var(--white);line-height:1.1;margin-bottom:1rem}
.hero h1 span{color:var(--light)}
.hero p{font-size:1.1rem;color:var(--muted);max-width:560px;margin:0 auto 2.5rem;line-height:1.7}
.hero-btns{display:flex;gap:1rem;justify-content:center;flex-wrap:wrap}
.btn-primary{background:linear-gradient(135deg,var(--accent),var(--light));color:#fff;padding:.75rem 2rem;border-radius:8px;text-decoration:none;font-weight:700;font-size:.95rem;transition:.2s}
.btn-primary:hover{transform:translateY(-2px)}
.btn-secondary{border:1px solid var(--border);color:var(--light);padding:.75rem 2rem;border-radius:8px;text-decoration:none;font-weight:600;font-size:.95rem;background:rgba(77,184,255,0.06);transition:.2s}
.stats{display:flex;gap:3rem;justify-content:center;flex-wrap:wrap;margin-top:4rem;padding-top:2rem;border-top:1px solid var(--border)}
.stat h3{font-size:1.8rem;font-weight:800;color:var(--light)}
.stat p{color:var(--muted);font-size:.82rem;margin-top:.2rem}
/* SECTIONS */
section{padding:5rem 2rem}
.container{max-width:1100px;margin:0 auto}
.section-header{text-align:center;margin-bottom:3.5rem}
.section-header .tag{color:var(--light);font-size:.78rem;font-weight:700;letter-spacing:2px;text-transform:uppercase;margin-bottom:.8rem;display:block}
.section-header h2{font-size:2rem;font-weight:800;color:var(--white);margin-bottom:.8rem}
.section-header p{color:var(--muted);max-width:520px;margin:0 auto;line-height:1.7}
#servicios{background:var(--bg2)}
.services-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:1.5rem}
.service-card{background:var(--card);border:1px solid var(--border);border-radius:14px;padding:2rem;transition:.25s;position:relative;overflow:hidden}
.service-card::before{content:'';position:absolute;top:0;left:0;right:0;height:2px;background:linear-gradient(90deg,var(--accent),var(--light));opacity:0;transition:.25s}
.service-card:hover{transform:translateY(-4px);border-color:rgba(77,184,255,0.35)}
.service-card:hover::before{opacity:1}
.service-icon{width:52px;height:52px;border-radius:12px;background:rgba(42,127,189,0.2);display:flex;align-items:center;justify-content:center;font-size:1.5rem;margin-bottom:1.2rem;border:1px solid rgba(77,184,255,0.2)}
.service-card h3{font-size:1.05rem;font-weight:700;color:var(--white);margin-bottom:.5rem}
.service-card p{font-size:.87rem;color:var(--muted);line-height:1.6;margin-bottom:1rem}
.service-card .price{color:var(--light);font-size:1rem;font-weight:800;margin-bottom:1rem}
.add-cart-btn{width:100%;background:rgba(77,184,255,0.1);border:1px solid rgba(77,184,255,0.3);color:var(--light);padding:.55rem;border-radius:8px;cursor:pointer;font-size:.85rem;font-weight:700;transition:.2s;display:flex;align-items:center;justify-content:center;gap:.4rem}
.add-cart-btn:hover{background:rgba(77,184,255,0.2)}
.add-cart-btn.added{background:rgba(40,200,64,0.15);border-color:rgba(40,200,64,0.4);color:var(--green)}
/* HOSTING PLANS */
#hosting{background:var(--bg)}
.plans-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:1.5rem}
.plan{background:var(--card);border:1px solid var(--border);border-radius:14px;padding:2rem;text-align:center;position:relative}
.plan.featured{border-color:var(--accent);background:linear-gradient(160deg,#142840,#0e2035);box-shadow:0 0 40px rgba(42,127,189,0.2)}
.plan-badge{position:absolute;top:-12px;left:50%;transform:translateX(-50%);background:linear-gradient(90deg,var(--accent),var(--light));color:#fff;font-size:.72rem;font-weight:700;padding:.3rem .9rem;border-radius:20px}
.plan h3{font-size:1rem;font-weight:700;color:var(--muted);margin-bottom:1rem;text-transform:uppercase;letter-spacing:1px}
.plan .price{font-size:2.4rem;font-weight:800;color:var(--white)}
.plan .price span{font-size:1rem;color:var(--muted);font-weight:400}
.plan ul{list-style:none;margin:1.5rem 0;text-align:left}
.plan ul li{padding:.4rem 0;color:var(--text);font-size:.88rem;display:flex;align-items:center;gap:.6rem}
.plan ul li::before{content:'✓';color:var(--light);font-weight:700}
.plan-btn{display:block;width:100%;padding:.7rem;border-radius:8px;font-weight:700;font-size:.9rem;cursor:pointer;border:none;transition:.2s;margin-bottom:.5rem}
.plan.featured .plan-btn{background:linear-gradient(135deg,var(--accent),var(--light));color:#fff}
.plan:not(.featured) .plan-btn{background:rgba(77,184,255,0.1);color:var(--light);border:1px solid var(--border)}
.plan-cart-btn{display:block;width:100%;padding:.55rem;border-radius:8px;font-weight:600;font-size:.82rem;cursor:pointer;border:1px solid rgba(77,184,255,0.3);background:rgba(77,184,255,0.06);color:var(--light);transition:.2s}
.plan-cart-btn:hover{background:rgba(77,184,255,0.15)}
/* ANTIDDOS */
#antiddos{background:var(--bg2)}
.ddos-grid{display:grid;grid-template-columns:1fr 1fr;gap:3rem;align-items:center}
@media(max-width:700px){.ddos-grid,.contact-wrapper{grid-template-columns:1fr}nav ul{display:none}}
.ddos-features{display:flex;flex-direction:column;gap:1.2rem}
.ddos-feature{display:flex;align-items:flex-start;gap:1rem;background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.2rem}
.ddos-feature .ico{font-size:1.4rem;background:rgba(42,127,189,0.2);width:44px;height:44px;border-radius:10px;display:flex;align-items:center;justify-content:center;flex-shrink:0}
.ddos-feature h4{color:var(--white);font-size:.95rem;margin-bottom:.3rem}
.ddos-feature p{color:var(--muted);font-size:.83rem;line-height:1.6}
.ddos-visual{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:2rem;text-align:center}
.shield{font-size:5rem;margin-bottom:1rem;animation:pulse 2.5s infinite}
@keyframes pulse{0%,100%{filter:drop-shadow(0 0 8px rgba(77,184,255,0.3))}50%{filter:drop-shadow(0 0 20px rgba(77,184,255,0.7))}}
.ddos-visual h3{font-size:1.3rem;font-weight:800;color:var(--white);margin-bottom:.5rem}
.ddos-visual p{color:var(--muted);font-size:.88rem}
.metric{display:flex;justify-content:space-around;margin-top:1.5rem}
.metric-item h4{font-size:1.4rem;font-weight:800;color:var(--light)}
.metric-item p{font-size:.75rem;color:var(--muted)}
/* REPARACIONES */
#reparaciones{background:var(--bg)}
.repair-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:1.2rem}
.repair-card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.5rem;text-align:center;transition:.2s}
.repair-card:hover{border-color:rgba(77,184,255,0.35);transform:translateY(-3px)}
.repair-card .ico{font-size:2rem;margin-bottom:.8rem}
.repair-card h4{color:var(--white);font-size:.95rem;font-weight:700;margin-bottom:.4rem}
.repair-card p{color:var(--muted);font-size:.82rem;line-height:1.6}
.repair-card .price-tag{color:var(--light);font-size:.85rem;font-weight:700;margin-top:.8rem;display:block}
/* PANELES */
#paneles{background:var(--bg2)}
.panels-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:1.5rem}
.panel-card{background:var(--card);border:1px solid var(--border);border-radius:14px;overflow:hidden;transition:.2s}
.panel-card:hover{border-color:rgba(77,184,255,0.35);transform:translateY(-3px)}
.panel-preview{background:linear-gradient(135deg,#0a1825,#142840);padding:1.5rem;border-bottom:1px solid var(--border);font-family:monospace;font-size:.78rem;color:var(--muted);min-height:90px}
.panel-preview .bar{display:flex;gap:.4rem;margin-bottom:.8rem}
.dot{width:10px;height:10px;border-radius:50%}.dot-r{background:#ff5f57}.dot-y{background:#febc2e}.dot-g{background:#28c840}
.panel-preview .line{color:var(--light);margin:.2rem 0}.panel-preview .line.dim{color:var(--muted);opacity:.6}
.panel-body{padding:1.5rem}
.panel-body h3{color:var(--white);font-size:1rem;font-weight:700;margin-bottom:.5rem}
.panel-body p{color:var(--muted);font-size:.85rem;line-height:1.6;margin-bottom:1rem}
.panel-tags{display:flex;gap:.5rem;flex-wrap:wrap}
.ptag{background:rgba(77,184,255,0.1);border:1px solid rgba(77,184,255,0.2);color:var(--light);font-size:.7rem;padding:.2rem .6rem;border-radius:10px}
/* CONTACTO */
#contacto{background:var(--bg)}
.contact-wrapper{display:grid;grid-template-columns:1fr 1fr;gap:3rem;align-items:start}
.contact-info h3{font-size:1.4rem;font-weight:800;color:var(--white);margin-bottom:1rem}
.contact-info p{color:var(--muted);line-height:1.7;margin-bottom:1.5rem;font-size:.92rem}
.contact-item{display:flex;align-items:center;gap:.8rem;padding:.8rem 1rem;background:var(--card);border:1px solid var(--border);border-radius:10px;margin-bottom:.8rem}
.contact-item .ico{font-size:1.2rem}
.contact-item p{color:var(--muted);font-size:.85rem;margin:0}
.contact-item strong{color:var(--white);display:block;font-size:.9rem}
.contact-form{background:var(--card);border:1px solid var(--border);border-radius:14px;padding:2rem}
.form-group{margin-bottom:1.2rem}
.form-group label{display:block;color:var(--muted);font-size:.82rem;margin-bottom:.4rem;font-weight:600}
.form-group input,.form-group textarea,.form-group select{width:100%;background:rgba(13,27,42,0.6);border:1px solid var(--border);color:var(--text);padding:.7rem 1rem;border-radius:8px;font-size:.9rem;outline:none;transition:.2s;font-family:inherit}
.form-group input:focus,.form-group textarea:focus,.form-group select:focus{border-color:var(--accent);box-shadow:0 0 0 3px rgba(42,127,189,0.15)}
.form-group select option{background:#112236}
.form-group textarea{min-height:100px;resize:vertical}
.btn-submit{width:100%;background:linear-gradient(135deg,var(--accent),var(--light));color:#fff;border:none;padding:.8rem;border-radius:8px;font-weight:700;font-size:.95rem;cursor:pointer;transition:.2s}
.btn-submit:hover{opacity:.9}
/* TOAST */
.toast{position:fixed;bottom:2rem;left:50%;transform:translateX(-50%);background:#1a7a4a;color:#fff;padding:.7rem 1.5rem;border-radius:10px;font-weight:600;font-size:.88rem;display:none;z-index:9999;box-shadow:0 4px 20px rgba(0,0,0,0.4)}
/* CART SIDEBAR */
.cart-overlay{position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:300;display:none;backdrop-filter:blur(4px)}
.cart-overlay.open{display:block}
.cart-sidebar{position:fixed;top:0;right:0;width:380px;max-width:100vw;height:100vh;background:var(--bg2);border-left:1px solid var(--border);z-index:301;display:flex;flex-direction:column;transform:translateX(100%);transition:.3s}
.cart-sidebar.open{transform:translateX(0)}
.cart-head{display:flex;align-items:center;justify-content:space-between;padding:1.2rem 1.5rem;border-bottom:1px solid var(--border)}
.cart-head h3{color:var(--white);font-weight:800;font-size:1rem}
.cart-close{background:none;border:none;color:var(--muted);font-size:1.4rem;cursor:pointer;transition:.2s}
.cart-close:hover{color:var(--white)}
.cart-items{flex:1;overflow-y:auto;padding:1rem 1.5rem}
.cart-item{display:flex;align-items:center;justify-content:space-between;background:var(--card);border:1px solid var(--border);border-radius:10px;padding:.9rem;margin-bottom:.7rem}
.cart-item-info h4{color:var(--white);font-size:.88rem;font-weight:700}
.cart-item-info p{color:var(--light);font-size:.8rem;margin-top:.2rem;font-weight:600}
.cart-item-del{background:none;border:none;color:#ff7070;cursor:pointer;font-size:1.1rem;padding:.2rem}
.cart-empty{text-align:center;color:var(--muted);padding:3rem 1rem;font-size:.9rem}
.cart-footer{padding:1.2rem 1.5rem;border-top:1px solid var(--border)}
.cart-total{display:flex;justify-content:space-between;align-items:center;margin-bottom:1rem}
.cart-total span{color:var(--muted);font-size:.88rem}
.cart-total strong{color:var(--white);font-size:1.2rem;font-weight:800}
.cart-chat-btn{width:100%;background:linear-gradient(135deg,var(--accent),var(--light));color:#fff;border:none;padding:.8rem;border-radius:8px;font-weight:700;font-size:.95rem;cursor:pointer;transition:.2s}
.cart-chat-btn:hover{opacity:.9}
/* CHAT WIDGET */
.chat-overlay{position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:400;display:none;align-items:center;justify-content:center;backdrop-filter:blur(4px)}
.chat-overlay.open{display:flex}
.chat-box{background:var(--bg2);border:1px solid var(--border);border-radius:16px;width:460px;max-width:95vw;max-height:90vh;display:flex;flex-direction:column;overflow:hidden}
.chat-header{background:linear-gradient(135deg,var(--accent),#1a5f8f);padding:1rem 1.2rem;display:flex;align-items:center;justify-content:space-between}
.chat-header h3{color:#fff;font-size:.95rem;font-weight:700}
.chat-header p{color:rgba(255,255,255,0.7);font-size:.75rem}
.chat-close{background:none;border:none;color:#fff;font-size:1.3rem;cursor:pointer;opacity:.8}
.chat-close:hover{opacity:1}
/* pre-chat form */
.pre-chat{padding:2rem;display:flex;flex-direction:column;gap:1rem}
.pre-chat h4{color:var(--white);font-size:1rem;font-weight:700;margin-bottom:.3rem}
.pre-chat p{color:var(--muted);font-size:.85rem;line-height:1.5}
.pre-chat input{background:rgba(13,27,42,0.7);border:1px solid var(--border);color:var(--text);padding:.7rem 1rem;border-radius:8px;font-size:.9rem;outline:none;transition:.2s;font-family:inherit}
.pre-chat input:focus{border-color:var(--accent)}
.pre-chat .cart-summary{background:var(--card);border:1px solid var(--border);border-radius:10px;padding:1rem;font-size:.83rem;color:var(--muted)}
.pre-chat .cart-summary strong{color:var(--white);display:block;margin-bottom:.4rem}
.start-btn{background:linear-gradient(135deg,var(--accent),var(--light));color:#fff;border:none;padding:.75rem;border-radius:8px;font-weight:700;font-size:.92rem;cursor:pointer;transition:.2s}
.start-btn:hover{opacity:.9}
/* chat messages */
.chat-msgs{flex:1;overflow-y:auto;padding:1rem;display:flex;flex-direction:column;gap:.6rem;min-height:250px}
.msg-bubble{max-width:80%;padding:.6rem .9rem;border-radius:12px;font-size:.87rem;line-height:1.5}
.msg-bubble.client{background:rgba(42,127,189,0.2);border:1px solid rgba(42,127,189,0.3);color:var(--text);align-self:flex-end;border-bottom-right-radius:4px}
.msg-bubble.employee{background:var(--card);border:1px solid var(--border);color:var(--text);align-self:flex-start;border-bottom-left-radius:4px}
.msg-bubble .sender{font-size:.72rem;font-weight:700;margin-bottom:.2rem;opacity:.7}
.msg-bubble.client .sender{color:var(--light)}
.msg-bubble.employee .sender{color:#aaa}
.chat-input-row{display:flex;gap:.5rem;padding:.8rem 1rem;border-top:1px solid var(--border)}
.chat-input-row input{flex:1;background:rgba(13,27,42,0.7);border:1px solid var(--border);color:var(--text);padding:.6rem .9rem;border-radius:8px;font-size:.88rem;outline:none;font-family:inherit}
.chat-input-row input:focus{border-color:var(--accent)}
.chat-send{background:var(--accent);color:#fff;border:none;padding:.6rem 1rem;border-radius:8px;cursor:pointer;font-weight:700;font-size:.85rem;transition:.2s;flex-shrink:0}
.chat-send:hover{background:var(--light);color:var(--bg)}
.chat-closed-msg{text-align:center;padding:1rem;color:var(--muted);font-size:.85rem;background:rgba(77,184,255,0.05);margin:.5rem}
footer{background:#080f18;border-top:1px solid var(--border);padding:2rem;text-align:center;color:var(--muted);font-size:.83rem}
footer span{color:var(--light)}
</style>
</head>
<body>

<!-- NAV -->
<nav>
  <div class="nav-logo">
    <div class="logo-icon">H</div>
    <div><span>Hugo's Solutions</span><small>Estepona · Málaga</small></div>
  </div>
  <ul>
    <li><a href="#servicios">Servicios</a></li>
    <li><a href="#hosting">Hosting</a></li>
    <li><a href="#antiddos">Anti-DDoS</a></li>
    <li><a href="#reparaciones">Reparaciones</a></li>
    <li><a href="#paneles">Paneles</a></li>
    <li><a href="#contacto">Contacto</a></li>
  </ul>
  <div class="nav-right">
    <a href="/login" class="nav-emp">🔒 Empleados</a>
    <button class="cart-btn" onclick="toggleCart()">
      🛒 Carrito <span class="cart-count" id="cartCount" style="display:none">0</span>
    </button>
  </div>
</nav>

<!-- HERO -->
<section class="hero">
  <div class="badge">✦ Soluciones tecnológicas en Estepona</div>
  <h1>Tecnología que<br/><span>protege y conecta</span></h1>
  <p>Redes, ciberseguridad, hosting, reparaciones y paneles de administración. Añade servicios al carrito y habla con nosotros en directo.</p>
  <div class="hero-btns">
    <a href="#servicios" class="btn-primary">Ver servicios</a>
    <a href="#contacto" class="btn-secondary">Contactar</a>
  </div>
  <div class="stats">
    <div class="stat"><h3>99.9%</h3><p>Uptime garantizado</p></div>
    <div class="stat"><h3>24/7</h3><p>Soporte técnico</p></div>
    <div class="stat"><h3>&lt;1ms</h3><p>Latencia media</p></div>
    <div class="stat"><h3>100%</h3><p>Clientes satisfechos</p></div>
  </div>
</section>

<!-- ANIMACION REDES canvas (oculto, se usa en seccion redes) -->
<!-- SERVICIOS -->
<section id="servicios"><div class="container">
  <div class="section-header"><span class="tag">¿Qué hacemos?</span><h2>Nuestros Servicios</h2><p>Añade los que necesites al carrito y te asesoramos en directo.</p></div>
  <div style="background:#0d1b2a;border-radius:14px;overflow:hidden;border:1px solid var(--border);margin-bottom:2rem">
    <canvas id="redes-anim" style="width:100%;display:block"></canvas>
  </div>
  <div class="services-grid">
    <div class="service-card">
      <div class="service-icon">🌐</div><h3>Soluciones de Redes</h3>
      <p>Diseño, instalación y mantenimiento de infraestructuras LAN/WAN, WiFi empresarial, VPNs y routers.</p>
      <div class="price">Desde 150€</div>
      <button class="add-cart-btn" onclick="addToCart(this,'Soluciones de Redes','Desde 150€')">🛒 Añadir al carrito</button>
    </div>
    <div class="service-card">
      <div class="service-icon">🛡️</div><h3>Protección Anti-DDoS</h3>
      <p>Mitigación de ataques en tiempo real. Protección L3/L4/L7 contra amenazas volumétricas.</p>
      <div class="price">Desde 29€/mes</div>
      <button class="add-cart-btn" onclick="addToCart(this,'Protección Anti-DDoS','Desde 29€/mes')">🛒 Añadir al carrito</button>
    </div>
    <div class="service-card">
      <div class="service-icon">🔧</div><h3>Reparaciones Informáticas</h3>
      <p>Diagnóstico y reparación de PC, portátiles, servidores. Presencial en Estepona.</p>
      <div class="price">Desde 20€</div>
      <button class="add-cart-btn" onclick="addToCart(this,'Reparaciones Informáticas','Desde 20€')">🛒 Añadir al carrito</button>
    </div>
    <div class="service-card">
      <div class="service-icon">⚙️</div><h3>Panel de Administración</h3>
      <p>Dashboard personalizado para gestionar tu web, usuarios y facturación desde un solo lugar.</p>
      <div class="price">Desde 200€</div>
      <button class="add-cart-btn" onclick="addToCart(this,'Panel de Administración','Desde 200€')">🛒 Añadir al carrito</button>
    </div>
    <div class="service-card">
      <div class="service-icon">🔒</div><h3>Ciberseguridad</h3>
      <p>Auditorías, firewalls, monitorización de redes y consultoría para proteger tu empresa.</p>
      <div class="price">Consultar precio</div>
      <button class="add-cart-btn" onclick="addToCart(this,'Ciberseguridad','Consultar precio')">🛒 Añadir al carrito</button>
    </div>
    <div class="service-card">
      <div class="service-icon">💾</div><h3>Recuperación de Datos</h3>
      <p>Recuperación de archivos en HDD, SSD, pendrive y tarjetas SD dañadas o formateadas.</p>
      <div class="price">Consultar precio</div>
      <button class="add-cart-btn" onclick="addToCart(this,'Recuperación de Datos','Consultar precio')">🛒 Añadir al carrito</button>
    </div>
  </div>
</div></section>

<!-- HOSTING -->
<section id="hosting"><div class="container">
  <div class="section-header"><span class="tag">Alojamiento web</span><h2>Planes de Hosting</h2><p>Servidores rápidos y seguros con soporte en español.</p></div>
  <div style="background:#0d1b2a;border-radius:14px;overflow:hidden;border:1px solid var(--border);margin-bottom:2rem">
    <canvas id="hosting-anim" style="width:100%;display:block"></canvas>
  </div>
  <div class="plans-grid">
    <div class="plan">
      <h3>Básico</h3><div class="price">9<span>€/mes</span></div>
      <ul><li>10 GB SSD NVMe</li><li>1 dominio</li><li>SSL gratuito</li><li>5 cuentas email</li><li>Backups semanales</li></ul>
      <button class="plan-cart-btn" onclick="addToCart(this,'Hosting Básico','9€/mes')">🛒 Añadir al carrito</button>
    </div>
    <div class="plan featured">
      <div class="plan-badge">⭐ Más popular</div>
      <h3>Profesional</h3><div class="price">24<span>€/mes</span></div>
      <ul><li>50 GB SSD NVMe</li><li>5 dominios</li><li>SSL gratuito</li><li>Emails ilimitados</li><li>Soporte 24/7</li><li>Backups diarios</li><li>Anti-DDoS básico</li></ul>
      <button class="plan-cart-btn" onclick="addToCart(this,'Hosting Profesional','24€/mes')">🛒 Añadir al carrito</button>
    </div>
    <div class="plan">
      <h3>Dedicado</h3><div class="price">79<span>€/mes</span></div>
      <ul><li>500 GB SSD NVMe</li><li>Dominios ilimitados</li><li>SSL wildcard</li><li>Soporte prioritario 24/7</li><li>Backups tiempo real</li><li>Anti-DDoS avanzado</li><li>IP dedicada</li></ul>
      <button class="plan-cart-btn" onclick="addToCart(this,'Hosting Dedicado','79€/mes')">🛒 Añadir al carrito</button>
    </div>
  </div>
</div></section>

<!-- ANTIDDOS -->
<section id="antiddos"><div class="container">
  <div class="section-header"><span class="tag">Ciberseguridad</span><h2>Protección Anti-DDoS</h2><p>Infraestructura protegida en tiempo real. Haz clic en la animación para activar el escudo.</p></div>
  <div class="ddos-grid">
    <div class="ddos-features">
      <div class="ddos-feature"><div class="ico">⚡</div><div><h4>Mitigación instantánea</h4><p>Bloqueo de ataques en menos de 10 segundos.</p></div></div>
      <div class="ddos-feature"><div class="ico">🔍</div><div><h4>Inspección de paquetes</h4><p>Análisis L3, L4 y L7 para separar tráfico legítimo.</p></div></div>
      <div class="ddos-feature"><div class="ico">📊</div><div><h4>Panel de monitorización</h4><p>Tráfico y ataques en tiempo real.</p></div></div>
      <div class="ddos-feature"><div class="ico">🌍</div><div><h4>Red global</h4><p>Scrubbing centers para ataques de hasta 1 Tbps.</p></div></div>
    </div>
    <div class="ddos-visual" style="padding:0;overflow:hidden;background:#0d1b2a">
      <canvas id="ddos" style="width:100%;display:block;cursor:pointer;border-radius:14px"></canvas>
    </div>
  </div>
  <div class="metric" style="margin-top:1.5rem"><div class="metric-item"><h4>1 Tbps</h4><p>Capacidad</p></div><div class="metric-item"><h4>&lt;10s</h4><p>Respuesta</p></div><div class="metric-item"><h4>99.99%</h4><p>Efectividad</p></div></div>
</div></section>

<!-- REPARACIONES -->
<section id="reparaciones"><div class="container">
  <div class="section-header"><span class="tag">Servicio técnico</span><h2>Reparaciones Informáticas</h2><p>Diagnóstico gratuito. Haz clic en el escáner para simular un diagnóstico.</p></div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:2rem;align-items:center;margin-bottom:2rem">
    <div style="background:#0d1b2a;border-radius:14px;overflow:hidden;border:1px solid var(--border)">
      <canvas id="repair" style="width:100%;display:block;cursor:pointer"></canvas>
    </div>
    <div class="repair-grid" style="grid-template-columns:1fr 1fr">
      <div class="repair-card"><div class="ico">💻</div><h4>Portátiles</h4><p>Pantallas, teclados, baterías.</p><span class="price-tag">Diagnóstico gratis</span></div>
      <div class="repair-card"><div class="ico">🖥️</div><h4>Sobremesa</h4><p>Montaje y reparación de PC.</p><span class="price-tag">Desde 20€</span></div>
      <div class="repair-card"><div class="ico">🖧</div><h4>Servidores</h4><p>Físicos y NAS.</p><span class="price-tag">Consultar</span></div>
      <div class="repair-card"><div class="ico">📱</div><h4>Móviles</h4><p>Pantallas y baterías.</p><span class="price-tag">Desde 15€</span></div>
    </div>
  </div>
</div></section>

<!-- PANELES -->
<section id="paneles"><div class="container">
  <div class="section-header"><span class="tag">Gestión</span><h2>Paneles de Administración</h2><p>Dashboards personalizados para tu negocio.</p></div>
  <div style="background:#0d1b2a;border-radius:14px;overflow:hidden;border:1px solid var(--border);margin-bottom:2rem">
    <canvas id="panel-anim" style="width:100%;display:block"></canvas>
  </div>
  <div class="panels-grid">
    <div class="panel-card"><div class="panel-preview"><div class="bar"><div class="dot dot-r"></div><div class="dot dot-y"></div><div class="dot dot-g"></div></div><div class="line">$ usuarios --listar</div><div class="line dim">▶ 142 usuarios activos</div><div class="line">$ servidor --estado</div><div class="line dim">▶ CPU: 12% | RAM: 4.2GB</div></div><div class="panel-body"><h3>Panel de Gestión Web</h3><p>Usuarios, pedidos y estadísticas centralizados.</p><div class="panel-tags"><span class="ptag">Usuarios</span><span class="ptag">Pedidos</span><span class="ptag">Analytics</span></div></div></div>
    <div class="panel-card"><div class="panel-preview"><div class="bar"><div class="dot dot-r"></div><div class="dot dot-y"></div><div class="dot dot-g"></div></div><div class="line">$ red --monitorizar</div><div class="line dim">▶ Latencia: 0.8ms ✓</div><div class="line">$ firewall --reglas</div><div class="line dim">▶ 48 reglas activas</div></div><div class="panel-body"><h3>Panel de Red y Seguridad</h3><p>Firewall y tráfico en tiempo real.</p><div class="panel-tags"><span class="ptag">Firewall</span><span class="ptag">Monitorización</span></div></div></div>
    <div class="panel-card"><div class="panel-preview"><div class="bar"><div class="dot dot-r"></div><div class="dot dot-y"></div><div class="dot dot-g"></div></div><div class="line">$ facturacion --mes</div><div class="line dim">▶ Ingresos: 4.820€</div><div class="line">$ clientes --nuevos</div><div class="line dim">▶ +12 este mes</div></div><div class="panel-body"><h3>Panel de Facturación</h3><p>Facturas y cobros automatizados.</p><div class="panel-tags"><span class="ptag">Facturas</span><span class="ptag">Clientes</span></div></div></div>
  </div>
</div></section>

<!-- CONTACTO -->
<section id="contacto"><div class="container">
  <div class="section-header"><span class="tag">Hablemos</span><h2>Contacto</h2><p>Cuéntanos qué necesitas y te respondemos en menos de 24h.</p></div>
  <div class="contact-wrapper">
    <div class="contact-info">
      <h3>Hugo's Solutions</h3>
      <p>Empresa de soluciones tecnológicas con sede en Estepona, Málaga. Atendemos clientes de toda la Costa del Sol y de forma remota a nivel nacional.</p>
      <div class="contact-item"><div class="ico">📍</div><div><strong>Ubicación</strong><p>Estepona, Málaga, España</p></div></div>
      <div class="contact-item"><div class="ico">🕐</div><div><strong>Horario</strong><p>Lunes – Viernes: 9:00 – 20:00</p></div></div>
      <div class="contact-item"><div class="ico">💬</div><div><strong>Soporte 24/7</strong><p>Para clientes con plan activo</p></div></div>
      <div class="contact-item"><div class="ico">🌍</div><div><strong>Cobertura</strong><p>Presencial Estepona · Online toda España</p></div></div>
    </div>
    <div class="contact-form">
      <div class="form-group"><label>Nombre completo</label><input id="c-name" type="text" placeholder="Tu nombre"/></div>
      <div class="form-group"><label>Correo electrónico</label><input id="c-email" type="email" placeholder="correo@ejemplo.com"/></div>
      <div class="form-group"><label>Servicio de interés</label>
        <select id="c-service"><option value="">Selecciona...</option><option>Soluciones de Redes</option><option>Protección Anti-DDoS</option><option>Alquiler de Hosting</option><option>Reparación Informática</option><option>Panel de Administración</option><option>Ciberseguridad</option><option>Otro</option></select>
      </div>
      <div class="form-group"><label>Mensaje</label><textarea id="c-msg" placeholder="Describe tu proyecto..."></textarea></div>
      <button class="btn-submit" id="sendBtn">Enviar mensaje</button>
    </div>
  </div>
</div></section>

<footer>
  <p>© 2025 <span>Hugo's Solutions</span> · Estepona, Málaga · Todos los derechos reservados</p>
  <p style="margin-top:.5rem;opacity:.6">Tecnología que protege y conecta</p>
</footer>

<div class="toast" id="toast"></div>

<!-- CART SIDEBAR -->
<div class="cart-overlay" id="cartOverlay" onclick="toggleCart()"></div>
<div class="cart-sidebar" id="cartSidebar">
  <div class="cart-head">
    <h3>🛒 Tu carrito</h3>
    <button class="cart-close" onclick="toggleCart()">✕</button>
  </div>
  <div class="cart-items" id="cartItems"></div>
  <div class="cart-footer">
    <div class="cart-total"><span>Servicios seleccionados:</span><strong id="cartTotalCount">0</strong></div>
    <button class="cart-chat-btn" onclick="openChat()">💬 Hablar con un asesor →</button>
  </div>
</div>

<!-- CHAT WIDGET -->
<div class="chat-overlay" id="chatOverlay">
  <div class="chat-box">
    <div class="chat-header">
      <div><h3>💬 Chat con Hugo's Solutions</h3><p id="chatHeaderSub">Asesoramiento en directo</p></div>
      <button class="chat-close" onclick="closeChat()">✕</button>
    </div>
    <!-- Pre-chat form -->
    <div class="pre-chat" id="preChatForm">
      <h4>Antes de empezar...</h4>
      <p>Introduce tus datos para que podamos identificarte y ayudarte mejor.</p>
      <input id="chatName" placeholder="Tu nombre completo"/>
      <input id="chatEmail" type="email" placeholder="Tu email (te responderemos aquí)"/>
      <div class="cart-summary" id="chatCartSummary"></div>
      <button class="start-btn" onclick="startChat()">Iniciar chat →</button>
    </div>
    <!-- Chat messages -->
    <div class="chat-msgs" id="chatMsgs" style="display:none"></div>
    <div class="chat-input-row" id="chatInputRow" style="display:none">
      <input id="chatInput" placeholder="Escribe tu mensaje..." onkeydown="if(event.key==='Enter')sendMsg()"/>
      <button class="chat-send" onclick="sendMsg()">Enviar</button>
    </div>
  </div>
</div>

<script>
const socket = io();
let cart = [];
let sessionId = null;
let clientName = '';

// ── CARRITO ──────────────────────────────────
function addToCart(btn, name, price) {
  if (cart.find(i=>i.name===name)) { showToast('Ya está en el carrito'); return; }
  cart.push({name, price});
  btn.textContent = '✓ Añadido';
  btn.classList.add('added');
  updateCartUI();
  showToast('✓ '+name+' añadido al carrito');
}
function removeFromCart(idx) {
  cart.splice(idx,1);
  updateCartUI();
  renderCartItems();
}
function updateCartUI() {
  const c = document.getElementById('cartCount');
  if (cart.length) { c.textContent=cart.length; c.style.display='flex'; }
  else c.style.display='none';
  renderCartItems();
}
function renderCartItems() {
  const el = document.getElementById('cartItems');
  if (!cart.length) { el.innerHTML='<div class="cart-empty">Tu carrito está vacío.<br/>Añade servicios desde la web.</div>'; return; }
  el.innerHTML = cart.map((i,idx)=>`
    <div class="cart-item">
      <div class="cart-item-info"><h4>${i.name}</h4><p>${i.price}</p></div>
      <button class="cart-item-del" onclick="removeFromCart(${idx})">🗑</button>
    </div>`).join('');
  document.getElementById('cartTotalCount').textContent = cart.length;
}
function toggleCart() {
  document.getElementById('cartOverlay').classList.toggle('open');
  document.getElementById('cartSidebar').classList.toggle('open');
  renderCartItems();
}

// ── CHAT ─────────────────────────────────────
function openChat() {
  if (!cart.length) { showToast('Añade algún servicio primero'); return; }
  toggleCart();
  const summary = document.getElementById('chatCartSummary');
  summary.innerHTML = '<strong>Servicios seleccionados:</strong>' + cart.map(i=>`<div style="margin-top:.3rem;color:#cde6f7">• ${i.name} — ${i.price}</div>`).join('');
  document.getElementById('chatOverlay').classList.add('open');
}
function closeChat() {
  document.getElementById('chatOverlay').classList.remove('open');
}
function startChat() {
  clientName = document.getElementById('chatName').value.trim();
  const email = document.getElementById('chatEmail').value.trim();
  if (!clientName||!email) { showToast('Introduce tu nombre y email'); return; }
  socket.emit('client_start', {name:clientName, email, cart:[...cart]});
}
socket.on('chat_started', ({sessionId: sid}) => {
  sessionId = sid;
  document.getElementById('preChatForm').style.display='none';
  document.getElementById('chatMsgs').style.display='flex';
  document.getElementById('chatInputRow').style.display='flex';
  document.getElementById('chatHeaderSub').textContent='Conectado — un asesor te atenderá en breve';
  addBubble('employee','Hugo\'s Solutions','¡Hola '+clientName+'! 👋 Hemos recibido tu selección de servicios. Un asesor te atenderá en breve.');
});
function sendMsg() {
  const inp = document.getElementById('chatInput');
  const msg = inp.value.trim();
  if (!msg||!sessionId) return;
  socket.emit('send_message',{sessionId, message:msg});
  inp.value='';
}
socket.on('new_message', (msg) => {
  addBubble(msg.sender, msg.sender_name, msg.message);
});
socket.on('chat_closed', () => {
  const row = document.getElementById('chatInputRow');
  row.innerHTML='<div class="chat-closed-msg">✓ Chat cerrado por el equipo. Revisa tu email para nuestra respuesta.</div>';
});
function addBubble(sender, name, text) {
  const el = document.getElementById('chatMsgs');
  el.innerHTML += `<div class="msg-bubble ${sender}"><div class="sender">${name}</div>${text}</div>`;
  el.scrollTop = el.scrollHeight;
}

// ── FORMULARIO CONTACTO ──────────────────────
document.getElementById('sendBtn').addEventListener('click', async () => {
  const name=document.getElementById('c-name').value.trim();
  const email=document.getElementById('c-email').value.trim();
  const service=document.getElementById('c-service').value;
  const message=document.getElementById('c-msg').value.trim();
  if(!name||!email||!message){showToast('Rellena nombre, email y mensaje');return}
  const res=await fetch('/api/contact',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,email,service,message})});
  if(res.ok){showToast('✔ Mensaje enviado correctamente');document.getElementById('c-name').value='';document.getElementById('c-email').value='';document.getElementById('c-service').value='';document.getElementById('c-msg').value='';}
});

function showToast(msg) {
  const t=document.getElementById('toast');
  t.textContent=msg; t.style.display='block';
  setTimeout(()=>t.style.display='none',3000);
}

// ══════════════════════════════════════════════
// ANIMACIONES
// ══════════════════════════════════════════════
function lerp(a,b,t){return a+(b-a)*t}
function rnd(a,b){return Math.random()*(b-a)+a}

// ── 1. ANTI-DDOS ─────────────────────────────
(()=>{
  const c=document.getElementById('ddos');
  if(!c)return;
  c.width=640;c.height=220;
  const ctx=c.getContext('2d');
  let shieldActive=false,shieldAlpha=0;
  const server={x:490,y:110};
  const attackers=[{x:60,y:50,col:'#ff4444'},{x:60,y:110,col:'#ff6622'},{x:60,y:170,col:'#ff2266'}];
  const packets=[];
  let blocked=[];
  attackers.forEach((a,i)=>{
    for(let j=0;j<4;j++) packets.push({ax:i,prog:-(j*0.25),blocked:false});
  });
  c.addEventListener('click',()=>{shieldActive=!shieldActive;blocked=[];});
  let t=0;
  function drawServer(x,y){
    ctx.fillStyle='#1a3a5c';ctx.strokeStyle='#d4721a';ctx.lineWidth=1.5;
    ctx.beginPath();ctx.roundRect(x-22,y-30,44,60,6);ctx.fill();ctx.stroke();
    for(let i=0;i<3;i++){ctx.fillStyle=i===0?'#d4721a':'#2a1f0e';ctx.beginPath();ctx.roundRect(x-14,y-22+i*18,28,12,2);ctx.fill();}
    ctx.fillStyle='#f0a050';ctx.beginPath();ctx.arc(x+10,y-15,3,0,Math.PI*2);ctx.fill();
  }
  function drawAttacker(x,y,col){
    ctx.fillStyle='#2a0a0a';ctx.strokeStyle=col;ctx.lineWidth=1.2;
    ctx.beginPath();ctx.roundRect(x-18,y-18,36,36,5);ctx.fill();ctx.stroke();
    ctx.fillStyle=col;ctx.font='bold 18px monospace';ctx.textAlign='center';ctx.textBaseline='middle';
    ctx.fillText('☠',x,y+1);
  }
  function frame(){
    ctx.clearRect(0,0,640,220);t+=0.016;
    attackers.forEach(a=>{ctx.strokeStyle='rgba(255,60,60,0.06)';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(a.x+18,a.y);ctx.lineTo(server.x-22,server.y);ctx.stroke();});
    packets.forEach(p=>{
      p.prog+=0.005;
      if(p.prog>1)p.prog=-rnd(0,0.4);
      if(p.prog<0)return;
      const a=attackers[p.ax];
      const tx=shieldActive?server.x-70:server.x-22;
      const px=lerp(a.x+18,tx,Math.min(p.prog,1));
      const py=lerp(a.y,server.y,Math.min(p.prog,1));
      if(shieldActive&&p.prog>=0.88&&!p.blocked){
        p.blocked=true;
        blocked.push({x:px,y:py,vx:rnd(-2,2),vy:rnd(-2,2),life:1});
        p.prog=-rnd(0,0.3);p.blocked=false;return;
      }
      ctx.fillStyle=a.col;ctx.shadowColor=a.col;ctx.shadowBlur=6;
      ctx.beginPath();ctx.arc(px,py,4,0,Math.PI*2);ctx.fill();ctx.shadowBlur=0;
    });
    blocked=blocked.filter(b=>b.life>0);
    blocked.forEach(b=>{b.x+=b.vx;b.y+=b.vy;b.life-=0.03;ctx.fillStyle=`rgba(255,200,0,${b.life})`;ctx.beginPath();ctx.arc(b.x,b.y,3,0,Math.PI*2);ctx.fill();});
    if(shieldActive)shieldAlpha=Math.min(shieldAlpha+0.05,1);
    else shieldAlpha=Math.max(shieldAlpha-0.05,0);
    if(shieldAlpha>0){
      const pulse=Math.sin(t*3)*0.05+0.95;
      ctx.save();ctx.globalAlpha=shieldAlpha;
      ctx.strokeStyle='#d4721a';ctx.lineWidth=2.5;
      ctx.beginPath();ctx.arc(server.x-10,server.y,55*pulse,0,Math.PI*2);ctx.stroke();
      ctx.fillStyle='rgba(212,114,26,0.08)';ctx.fill();
      ctx.font='bold 30px serif';ctx.fillStyle=`rgba(212,114,26,${shieldAlpha})`;
      ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText('🛡',server.x-10,server.y);
      ctx.restore();
    }
    attackers.forEach(a=>drawAttacker(a.x,a.y,a.col));
    drawServer(server.x,server.y);
    ctx.fillStyle=shieldActive?'#d4721a':'rgba(255,100,100,0.7)';
    ctx.font='11px monospace';ctx.textAlign='center';ctx.textBaseline='top';
    ctx.fillText(shieldActive?'🛡 ESCUDO ACTIVO — paquetes bloqueados':'⚠ BAJO ATAQUE — haz clic para activar el escudo',320,6);
    requestAnimationFrame(frame);
  }
  frame();
})();

// ── 2. REDES ─────────────────────────────────
(()=>{
  const c=document.getElementById('redes-anim');
  if(!c)return;
  c.width=640;c.height=160;
  const ctx=c.getContext('2d');
  const nodes=[{x:60,y:80,label:'PC'},{x:180,y:35,label:'Switch'},{x:180,y:125,label:'WiFi'},{x:320,y:80,label:'Router'},{x:460,y:35,label:'VPN'},{x:460,y:125,label:'LAN'},{x:580,y:80,label:'Internet'}];
  const edges=[[0,1],[0,2],[1,3],[2,3],[3,4],[3,5],[4,6],[5,6]];
  const pkts=edges.map(e=>({edge:e,prog:Math.random(),dir:1}));
  function drawNode(n){
    ctx.fillStyle='#2a1f0e';ctx.strokeStyle='#d4721a';ctx.lineWidth=1.2;
    ctx.beginPath();ctx.roundRect(n.x-22,n.y-13,44,26,5);ctx.fill();ctx.stroke();
    ctx.fillStyle='#f5dfc0';ctx.font='11px sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';
    ctx.fillText(n.label,n.x,n.y);
  }
  function frame(){
    ctx.clearRect(0,0,640,160);
    edges.forEach(([a,b])=>{ctx.strokeStyle='rgba(212,114,26,0.15)';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(nodes[a].x,nodes[a].y);ctx.lineTo(nodes[b].x,nodes[b].y);ctx.stroke();});
    pkts.forEach(p=>{
      p.prog+=0.007*p.dir;
      if(p.prog>1){p.prog=1;p.dir=-1;}if(p.prog<0){p.prog=0;p.dir=1;}
      const [ai,bi]=p.edge;const na=nodes[ai],nb=nodes[bi];
      const px=lerp(na.x,nb.x,p.prog),py=lerp(na.y,nb.y,p.prog);
      ctx.fillStyle='#f0a050';ctx.shadowColor='#f0a050';ctx.shadowBlur=8;
      ctx.beginPath();ctx.arc(px,py,4,0,Math.PI*2);ctx.fill();ctx.shadowBlur=0;
    });
    nodes.forEach(drawNode);
    requestAnimationFrame(frame);
  }
  frame();
})();

// ── 3. HOSTING ───────────────────────────────
(()=>{
  const c=document.getElementById('hosting-anim');
  if(!c)return;
  c.width=640;c.height=160;
  const ctx=c.getContext('2d');
  const servers=[{x:120,label:'Básico',ramVal:40},{x:320,label:'Profesional',ramVal:65},{x:520,label:'Dedicado',ramVal:80}];
  const requests=Array.from({length:8},()=>({x:rnd(40,600),y:rnd(10,40),vy:rnd(0.4,1.2),alpha:rnd(0.3,0.8)}));
  function drawSrv(s,cpu,ram){
    const x=s.x,y=20;
    ctx.fillStyle='#1a1208';ctx.strokeStyle='#d4721a';ctx.lineWidth=1.2;
    ctx.beginPath();ctx.roundRect(x-75,y,150,128,8);ctx.fill();ctx.stroke();
    ctx.fillStyle='#f0a050';ctx.font='bold 12px sans-serif';ctx.textAlign='center';ctx.textBaseline='top';
    ctx.fillText(s.label,x,y+8);
    const led=cpu<60?'#7ac840':cpu<80?'#f0c040':'#e05050';
    ctx.fillStyle=led;ctx.shadowColor=led;ctx.shadowBlur=8;
    ctx.beginPath();ctx.arc(x+58,y+10,5,0,Math.PI*2);ctx.fill();ctx.shadowBlur=0;
    [[cpu,'#d4721a','CPU'],[ram,'#f0a050','RAM'],[45,'#7ac840','SSD']].forEach(([v,col,lbl],i)=>{
      ctx.fillStyle='#2a1f0e';ctx.beginPath();ctx.roundRect(x-58,y+30+i*30,116,10,3);ctx.fill();
      ctx.fillStyle=col;ctx.beginPath();ctx.roundRect(x-58,y+30+i*30,116*(v/100),10,3);ctx.fill();
      ctx.fillStyle='#c4a07a';ctx.font='10px sans-serif';ctx.textAlign='left';ctx.textBaseline='top';
      ctx.fillText(lbl+' '+Math.round(v)+'%',x-58,y+44+i*30);
    });
  }
  function frame(){
    ctx.clearRect(0,0,640,160);
    const now=Date.now();
    requests.forEach(r=>{r.y+=r.vy;if(r.y>170)r.y=-10;ctx.fillStyle=`rgba(212,114,26,${r.alpha})`;ctx.beginPath();ctx.arc(r.x,r.y,2,0,Math.PI*2);ctx.fill();});
    servers.forEach((s,i)=>drawSrv(s,30+Math.sin(now/800+i)*18+i*12,s.ramVal));
    requestAnimationFrame(frame);
  }
  frame();
})();

// ── 4. REPARACIONES ──────────────────────────
(()=>{
  const c=document.getElementById('repair');
  if(!c)return;
  c.width=640;c.height=200;
  const ctx=c.getContext('2d');
  let scanY=0,scanDir=1,fallo=false,falloAlpha=0;
  c.addEventListener('click',()=>fallo=!fallo);
  function drawPC(){
    ctx.fillStyle='#1a1208';ctx.strokeStyle='#d4721a';ctx.lineWidth=1.5;
    ctx.beginPath();ctx.roundRect(160,15,320,140,8);ctx.fill();ctx.stroke();
    ctx.fillStyle='#080808';ctx.beginPath();ctx.roundRect(170,23,300,120,4);ctx.fill();
    ctx.fillStyle='#2a1f0e';ctx.strokeStyle='#d4721a';ctx.lineWidth=1;
    ctx.beginPath();ctx.moveTo(270,155);ctx.lineTo(370,155);ctx.lineTo(380,172);ctx.lineTo(260,172);ctx.closePath();ctx.fill();ctx.stroke();
    ctx.beginPath();ctx.roundRect(240,169,160,10,3);ctx.fill();ctx.stroke();
  }
  function frame(){
    ctx.clearRect(0,0,640,200);
    drawPC();
    scanY+=1.2*scanDir;if(scanY>118)scanDir=-1;if(scanY<0)scanDir=1;
    const sy=23+scanY;
    const g=ctx.createLinearGradient(170,sy-8,170,sy+8);
    g.addColorStop(0,'rgba(212,114,26,0)');g.addColorStop(0.5,'rgba(212,114,26,0.45)');g.addColorStop(1,'rgba(212,114,26,0)');
    ctx.fillStyle=g;ctx.fillRect(170,sy-8,300,16);
    ctx.fillStyle='rgba(240,160,80,0.55)';ctx.font='10px monospace';ctx.textAlign='left';ctx.textBaseline='top';
    ctx.fillText('> SCANNING SYSTEM...',178,30);
    ctx.fillText('> CPU: OK  RAM: OK  DISK: OK',178,46);
    ctx.fillText('> BIOS: OK  TEMP: 62°C  FANS: OK',178,60);
    if(fallo){
      falloAlpha=Math.min(falloAlpha+0.05,1);
      ctx.fillStyle=`rgba(224,80,80,${falloAlpha})`;ctx.font='bold 11px monospace';
      ctx.fillText('⚠ ERROR: Sector defectuoso en HDD [sector 0x4F2A]',178,80);
      ctx.fillText('⚠ RAM SLOT 2: fallo de paridad detectado',178,96);
      ctx.fillText('⚠ TEMP CPU: 94°C — refrigeración insuficiente',178,112);
    } else {falloAlpha=Math.max(falloAlpha-0.05,0);}
    ctx.fillStyle='#c4a07a';ctx.font='11px sans-serif';ctx.textAlign='center';ctx.textBaseline='top';
    ctx.fillText(fallo?'⚠ Fallos detectados — clic para resetear':'Escaneando... clic para simular fallo detectado',320,4);
    requestAnimationFrame(frame);
  }
  frame();
})();

// ── 5. PANEL / DASHBOARD ─────────────────────
(()=>{
  const c=document.getElementById('panel-anim');
  if(!c)return;
  c.width=640;c.height=160;
  const ctx=c.getContext('2d');
  const history=Array.from({length:40},()=>rnd(20,80));
  let t=0;
  function frame(){
    ctx.clearRect(0,0,640,160);t+=0.02;
    history.push(rnd(20,80));if(history.length>50)history.shift();
    const cards=[{label:'Usuarios',val:Math.round(140+Math.sin(t*0.7)*8),col:'#f0a050'},{label:'Ventas hoy',val:'€'+Math.round(820+Math.sin(t*0.5)*60),col:'#7ac840'},{label:'Chats',val:Math.round(3+Math.abs(Math.sin(t*0.9))*4),col:'#4db8ff'}];
    cards.forEach((card,i)=>{
      const x=20+i*130,y=10;
      ctx.fillStyle='#2a1f0e';ctx.strokeStyle='rgba(240,160,80,0.2)';ctx.lineWidth=0.8;
      ctx.beginPath();ctx.roundRect(x,y,118,50,6);ctx.fill();ctx.stroke();
      ctx.fillStyle=card.col;ctx.font='bold 18px sans-serif';ctx.textAlign='left';ctx.textBaseline='top';ctx.fillText(String(card.val),x+8,y+8);
      ctx.fillStyle='#c4a07a';ctx.font='10px sans-serif';ctx.fillText(card.label,x+8,y+34);
    });
    const bars=[{label:'Redes',v:0.7},{label:'Hosting',v:0.45},{label:'DDoS',v:0.3}];
    bars.forEach((b,i)=>{
      const bx=20+i*130,by=78;
      ctx.fillStyle='#2a1f0e';ctx.beginPath();ctx.roundRect(bx,by,118,8,3);ctx.fill();
      const fill=Math.min(b.v+Math.sin(t*0.8+i)*0.05,1);
      ctx.fillStyle='#d4721a';ctx.beginPath();ctx.roundRect(bx,by,118*fill,8,3);ctx.fill();
      ctx.fillStyle='#c4a07a';ctx.font='10px sans-serif';ctx.textAlign='left';ctx.textBaseline='top';
      ctx.fillText(b.label+' — '+Math.round(fill*100)+'%',bx,by+12);
    });
    const gx=420,gy=10,gw=200,gh=142;
    ctx.fillStyle='#1a1208';ctx.strokeStyle='rgba(240,160,80,0.2)';ctx.lineWidth=0.8;
    ctx.beginPath();ctx.roundRect(gx,gy,gw,gh,6);ctx.fill();ctx.stroke();
    ctx.fillStyle='#c4a07a';ctx.font='10px sans-serif';ctx.textAlign='left';ctx.textBaseline='top';ctx.fillText('Actividad en vivo',gx+8,gy+6);
    const pts=history.slice(-28);const stepX=gw/pts.length;
    ctx.beginPath();
    pts.forEach((v,i)=>{const px=gx+i*stepX,py=gy+gh-8-(v/100)*(gh-22);i===0?ctx.moveTo(px,py):ctx.lineTo(px,py);});
    ctx.strokeStyle='#d4721a';ctx.lineWidth=1.5;ctx.stroke();
    ctx.lineTo(gx+pts.length*stepX,gy+gh-8);ctx.lineTo(gx,gy+gh-8);ctx.closePath();
    ctx.fillStyle='rgba(212,114,26,0.1)';ctx.fill();
    requestAnimationFrame(frame);
  }
  frame();
})();
</script>
</body>
</html>
HTMLEOF
ok "index.html generado"

# ══════════════════════════════════════════════
step "Generando login.html..."
cat > "$PROJECT_DIR/public/login.html" << 'LOGINEOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Login — Hugo's Solutions</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0d1b2a;font-family:'Segoe UI',Arial,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center}
.wrap{width:100%;max-width:420px;padding:2rem}
.logo{text-align:center;margin-bottom:2rem}
.logo-icon{width:56px;height:56px;border-radius:14px;background:linear-gradient(135deg,#2a7fbd,#4db8ff);display:flex;align-items:center;justify-content:center;font-size:1.8rem;font-weight:900;color:#fff;margin:0 auto .8rem}
.logo h1{color:#f0f8ff;font-size:1.3rem;font-weight:800}
.logo p{color:#7ab3d4;font-size:.82rem;margin-top:.3rem}
.card{background:#142840;border:1px solid rgba(77,184,255,0.15);border-radius:16px;padding:2rem}
.card h2{color:#f0f8ff;font-size:1.1rem;font-weight:700;margin-bottom:1.5rem;text-align:center}
.fg{margin-bottom:1.2rem}
.fg label{display:block;color:#7ab3d4;font-size:.82rem;margin-bottom:.4rem;font-weight:600}
.fg input{width:100%;background:rgba(13,27,42,0.7);border:1px solid rgba(77,184,255,0.15);color:#cde6f7;padding:.75rem 1rem;border-radius:8px;font-size:.92rem;outline:none;transition:.2s;font-family:inherit}
.fg input:focus{border-color:#2a7fbd;box-shadow:0 0 0 3px rgba(42,127,189,0.15)}
.btn{width:100%;background:linear-gradient(135deg,#2a7fbd,#4db8ff);color:#fff;border:none;padding:.8rem;border-radius:8px;font-weight:700;font-size:.95rem;cursor:pointer;margin-top:.5rem}
.err{background:rgba(220,50,50,0.15);border:1px solid rgba(220,50,50,0.4);color:#ff7070;padding:.7rem 1rem;border-radius:8px;font-size:.85rem;margin-bottom:1rem;display:none;text-align:center}
.back{text-align:center;margin-top:1.2rem}
.back a{color:#7ab3d4;font-size:.82rem;text-decoration:none}
.back a:hover{color:#4db8ff}
</style>
</head>
<body>
<div class="wrap">
  <div class="logo">
    <div class="logo-icon">H</div>
    <h1>Hugo's Solutions</h1><p>Acceso para empleados</p>
  </div>
  <div class="card">
    <h2>🔒 Iniciar sesión</h2>
    <div class="err" id="err">Credenciales incorrectas</div>
    <div class="fg"><label>Email</label><input id="email" type="email" placeholder="empleado@hugos.com"/></div>
    <div class="fg"><label>Contraseña</label><input id="pass" type="password" placeholder="••••••••"/></div>
    <button class="btn" id="loginBtn">Entrar al panel</button>
  </div>
  <div class="back"><a href="/">← Volver a la web</a></div>
</div>
<script>
document.getElementById('loginBtn').addEventListener('click', async()=>{
  const email=document.getElementById('email').value;
  const password=document.getElementById('pass').value;
  document.getElementById('err').style.display='none';
  const r=await fetch('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password})});
  if(r.ok) window.location.href='/panel';
  else document.getElementById('err').style.display='block';
});
document.addEventListener('keydown',e=>{if(e.key==='Enter')document.getElementById('loginBtn').click()});
</script>
</body>
</html>
LOGINEOF
ok "login.html generado"

# ══════════════════════════════════════════════
step "Generando panel.html (panel completo de empleados)..."
cat > "$PROJECT_DIR/public/panel.html" << 'PANELEOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Panel — Hugo's Solutions</title>
<script src="/socket.io/socket.io.js"></script>
<style>
:root{--bg:#120d04;--sidebar:#1a1208;--card:#221808;--card2:#2a1f0e;--accent:#d4721a;--light:#f0a050;--text:#f5dfc0;--muted:#c4a07a;--white:#fff8f0;--border:rgba(240,160,80,0.15);--green:#7ac840;--red:#e05050;--yellow:#f0c040}
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--text);font-family:'Segoe UI',Arial,sans-serif;display:flex;min-height:100vh}
.sidebar{width:220px;background:var(--sidebar);border-right:1px solid var(--border);display:flex;flex-direction:column;position:fixed;top:0;left:0;height:100vh;z-index:50}
.sb-logo{padding:1.2rem 1rem;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:.6rem}
.logo-icon{width:34px;height:34px;border-radius:8px;background:linear-gradient(135deg,var(--accent),var(--light));display:flex;align-items:center;justify-content:center;font-size:1.1rem;font-weight:900;color:#fff;flex-shrink:0}
.sb-logo span{font-size:.9rem;font-weight:700;color:var(--white)}
.sb-logo small{color:var(--muted);font-size:.65rem;display:block}
.sb-nav{flex:1;padding:.8rem 0;overflow-y:auto}
.sb-item{display:flex;align-items:center;gap:.7rem;padding:.65rem 1rem;cursor:pointer;color:var(--muted);font-size:.85rem;font-weight:500;transition:.2s;border-left:3px solid transparent;user-select:none}
.sb-item:hover{color:var(--light);background:rgba(77,184,255,0.06)}
.sb-item.active{color:var(--light);background:rgba(77,184,255,0.1);border-left-color:var(--light)}
.sb-item .ico{font-size:1rem;width:20px;text-align:center;flex-shrink:0}
.sb-badge{margin-left:auto;background:var(--red);color:#fff;font-size:.65rem;padding:.1rem .45rem;border-radius:8px;font-weight:700}
.sb-footer{padding:.8rem 1rem;border-top:1px solid var(--border)}
.user-info{display:flex;align-items:center;gap:.5rem;margin-bottom:.7rem}
.user-avatar{width:30px;height:30px;border-radius:50%;background:linear-gradient(135deg,var(--accent),var(--light));display:flex;align-items:center;justify-content:center;font-size:.82rem;font-weight:700;color:#fff;flex-shrink:0}
.user-info div span{display:block;color:var(--white);font-size:.8rem;font-weight:600}
.user-info div small{color:var(--muted);font-size:.68rem}
.logout-btn{width:100%;background:rgba(255,95,87,0.1);border:1px solid rgba(255,95,87,0.3);color:#ff7070;padding:.45rem;border-radius:7px;cursor:pointer;font-size:.8rem;font-weight:600;transition:.2s}
.logout-btn:hover{background:rgba(255,95,87,0.2)}
.main{margin-left:220px;flex:1;padding:1.8rem;min-height:100vh}
.page{display:none}.page.active{display:block}
.page-title{font-size:1.3rem;font-weight:800;color:var(--white);margin-bottom:.2rem}
.page-sub{color:var(--muted);font-size:.85rem;margin-bottom:1.8rem}
/* STATS */
.stats-row{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:1rem;margin-bottom:1.8rem}
.stat-card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.1rem}
.stat-card .label{color:var(--muted);font-size:.75rem;font-weight:600;text-transform:uppercase;letter-spacing:.5px;margin-bottom:.4rem}
.stat-card .val{font-size:1.9rem;font-weight:800;color:var(--white)}
.stat-card .val.blue{color:var(--light)}.stat-card .val.green{color:var(--green)}.stat-card .val.yellow{color:var(--yellow)}.stat-card .val.red{color:var(--red)}
.stat-card .hint{color:var(--muted);font-size:.72rem;margin-top:.2rem}
/* CHART */
.chart-card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.3rem;margin-bottom:1.5rem}
.chart-card h3{color:var(--white);font-size:.92rem;font-weight:700;margin-bottom:1rem}
.bar-row{display:flex;align-items:center;gap:.7rem;margin-bottom:.6rem}
.bar-label{color:var(--muted);font-size:.78rem;width:170px;flex-shrink:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar-track{flex:1;background:rgba(77,184,255,0.1);border-radius:4px;height:9px;overflow:hidden}
.bar-fill{height:100%;background:linear-gradient(90deg,var(--accent),var(--light));border-radius:4px}
.bar-count{color:var(--light);font-size:.78rem;font-weight:700;width:20px;text-align:right}
/* MESSAGES */
.msg-filters{display:flex;gap:.4rem;margin-bottom:1rem;flex-wrap:wrap}
.filter-btn{background:rgba(77,184,255,0.08);border:1px solid var(--border);color:var(--muted);padding:.3rem .8rem;border-radius:20px;cursor:pointer;font-size:.78rem;font-weight:600;transition:.2s}
.filter-btn.active,.filter-btn:hover{background:rgba(77,184,255,0.18);color:var(--light);border-color:rgba(77,184,255,0.4)}
.msg-list{display:flex;flex-direction:column;gap:.7rem}
.msg-card{background:var(--card);border:1px solid var(--border);border-radius:11px;padding:1.1rem;transition:.2s}
.msg-card.unread{border-left:3px solid var(--light)}
.msg-card.read{border-left:3px solid rgba(77,184,255,0.2);opacity:.85}
.msg-head{display:flex;align-items:center;gap:.6rem;margin-bottom:.5rem;flex-wrap:wrap}
.msg-name{color:var(--white);font-weight:700;font-size:.9rem}
.msg-email-tag{background:rgba(77,184,255,0.12);border:1px solid rgba(77,184,255,0.2);color:var(--light);font-size:.72rem;padding:.15rem .55rem;border-radius:8px;font-family:monospace}
.msg-service{background:rgba(40,200,64,0.1);border:1px solid rgba(40,200,64,0.2);color:var(--green);font-size:.7rem;padding:.15rem .55rem;border-radius:8px;margin-left:auto}
.msg-date{color:var(--muted);font-size:.72rem}
.msg-body{color:var(--text);font-size:.87rem;line-height:1.6;margin-bottom:.7rem}
.msg-actions{display:flex;gap:.4rem;flex-wrap:wrap}
.act-btn{padding:.28rem .7rem;border-radius:6px;font-size:.75rem;font-weight:600;cursor:pointer;border:1px solid;transition:.2s}
.act-read{background:rgba(40,200,64,0.1);border-color:rgba(40,200,64,0.3);color:var(--green)}
.act-unread{background:rgba(77,184,255,0.1);border-color:rgba(77,184,255,0.3);color:var(--light)}
.act-del{background:rgba(255,95,87,0.1);border-color:rgba(255,95,87,0.3);color:var(--red)}
.status-dot{width:7px;height:7px;border-radius:50%;display:inline-block;margin-right:.3rem}
.dot-unread{background:var(--light)}.dot-read{background:var(--muted)}
/* CHAT PANEL */
.chat-layout{display:grid;grid-template-columns:280px 1fr;gap:1rem;height:calc(100vh - 140px)}
.chat-list{background:var(--card);border:1px solid var(--border);border-radius:12px;overflow-y:auto}
.chat-list-head{padding:.8rem 1rem;border-bottom:1px solid var(--border);color:var(--white);font-size:.88rem;font-weight:700}
.chat-session{padding:.8rem 1rem;border-bottom:1px solid rgba(77,184,255,0.07);cursor:pointer;transition:.2s}
.chat-session:hover{background:rgba(77,184,255,0.06)}
.chat-session.active{background:rgba(77,184,255,0.1);border-left:3px solid var(--light)}
.chat-session h4{color:var(--white);font-size:.85rem;font-weight:700;margin-bottom:.2rem}
.chat-session .cs-email{color:var(--light);font-size:.72rem;font-family:monospace;margin-bottom:.3rem}
.chat-session .cs-cart{color:var(--muted);font-size:.72rem;margin-bottom:.2rem}
.chat-session .cs-time{color:var(--muted);font-size:.7rem}
.cs-status{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:.3rem}
.cs-open{background:var(--green)}.cs-closed{background:var(--muted)}
.chat-window{background:var(--card);border:1px solid var(--border);border-radius:12px;display:flex;flex-direction:column;overflow:hidden}
.chat-win-head{padding:.8rem 1.2rem;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between}
.chat-win-head h3{color:var(--white);font-size:.9rem;font-weight:700}
.chat-win-head p{color:var(--muted);font-size:.75rem;margin-top:.1rem}
.close-chat-btn{background:rgba(255,95,87,0.1);border:1px solid rgba(255,95,87,0.3);color:var(--red);padding:.3rem .7rem;border-radius:6px;cursor:pointer;font-size:.75rem;font-weight:600}
.chat-msgs-panel{flex:1;overflow-y:auto;padding:1rem;display:flex;flex-direction:column;gap:.5rem}
.msg-bubble{max-width:75%;padding:.55rem .85rem;border-radius:11px;font-size:.86rem;line-height:1.5}
.msg-bubble.client{background:rgba(42,127,189,0.18);border:1px solid rgba(42,127,189,0.28);color:var(--text);align-self:flex-start;border-bottom-left-radius:3px}
.msg-bubble.employee{background:rgba(77,184,255,0.12);border:1px solid rgba(77,184,255,0.22);color:var(--text);align-self:flex-end;border-bottom-right-radius:3px}
.msg-bubble .sender{font-size:.7rem;font-weight:700;margin-bottom:.2rem;opacity:.7}
.msg-bubble.client .sender{color:var(--muted)}.msg-bubble.employee .sender{color:var(--light)}
.msg-bubble .mtime{font-size:.68rem;color:var(--muted);margin-top:.2rem;text-align:right}
.chat-reply{display:flex;gap:.5rem;padding:.7rem 1rem;border-top:1px solid var(--border)}
.chat-reply input{flex:1;background:rgba(10,21,32,0.7);border:1px solid var(--border);color:var(--text);padding:.55rem .8rem;border-radius:7px;font-size:.87rem;outline:none;font-family:inherit}
.chat-reply input:focus{border-color:var(--accent)}
.chat-reply button{background:var(--accent);color:#fff;border:none;padding:.55rem 1rem;border-radius:7px;cursor:pointer;font-weight:700;font-size:.82rem;flex-shrink:0}
.chat-reply button:hover{background:var(--light);color:var(--bg)}
.no-chat{display:flex;align-items:center;justify-content:center;height:100%;color:var(--muted);font-size:.9rem}
/* EMPLEADOS */
.emp-table{width:100%;border-collapse:collapse}
.emp-table th{text-align:left;color:var(--muted);font-size:.75rem;font-weight:600;text-transform:uppercase;letter-spacing:.5px;padding:.55rem .7rem;border-bottom:1px solid var(--border)}
.emp-table td{padding:.75rem .7rem;border-bottom:1px solid rgba(77,184,255,0.07);color:var(--text);font-size:.86rem}
.emp-table tr:hover td{background:rgba(77,184,255,0.03)}
.role-badge{padding:.2rem .6rem;border-radius:10px;font-size:.7rem;font-weight:700}
.role-admin{background:rgba(77,184,255,0.15);color:var(--light)}
.role-employee{background:rgba(40,200,64,0.12);color:var(--green)}
.two-col{display:grid;grid-template-columns:1fr 1fr;gap:1.2rem}
.form-block{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.3rem}
.form-block h3{color:var(--white);font-size:.9rem;font-weight:700;margin-bottom:1rem}
.fg{margin-bottom:.9rem}
.fg label{display:block;color:var(--muted);font-size:.76rem;margin-bottom:.3rem;font-weight:600}
.fg input,.fg select{width:100%;background:rgba(10,21,32,0.7);border:1px solid var(--border);color:var(--text);padding:.58rem .8rem;border-radius:7px;font-size:.86rem;outline:none;transition:.2s;font-family:inherit}
.fg input:focus,.fg select:focus{border-color:var(--accent)}
.fg select option{background:#112236}
.action-btn{background:linear-gradient(135deg,var(--accent),var(--light));color:#fff;border:none;padding:.6rem 1.3rem;border-radius:7px;font-weight:700;font-size:.85rem;cursor:pointer;transition:.2s}
.action-btn:hover{opacity:.9}
.emp-table-card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.3rem;margin-bottom:1.2rem;overflow-x:auto}
.empty{text-align:center;color:var(--muted);padding:2.5rem;font-size:.88rem}
.toast-p{position:fixed;bottom:1.5rem;right:1.5rem;background:#1a5c2a;color:#fff;padding:.6rem 1.2rem;border-radius:9px;font-weight:600;font-size:.85rem;display:none;z-index:999;box-shadow:0 4px 15px rgba(0,0,0,0.3)}
.toast-p.err{background:#7a1a1a}
</style>
</head>
<body>

<aside class="sidebar">
  <div class="sb-logo">
    <div class="logo-icon">H</div>
    <div><span>Hugo's Solutions</span><small>Panel interno</small></div>
  </div>
  <nav class="sb-nav">
    <div class="sb-item active" onclick="showPage('dashboard')"><span class="ico">📊</span> Dashboard</div>
    <div class="sb-item" onclick="showPage('messages')" id="nav-messages"><span class="ico">✉️</span> Mensajes <span class="sb-badge" id="badge-unread" style="display:none">0</span></div>
    <div class="sb-item" onclick="showPage('chat')" id="nav-chat"><span class="ico">💬</span> Chat en vivo <span class="sb-badge" id="badge-chat" style="display:none">!</span></div>
    <div class="sb-item admin-only" onclick="showPage('employees')"><span class="ico">👥</span> Empleados</div>
  </nav>
  <div class="sb-footer">
    <div class="user-info">
      <div class="user-avatar" id="userAvatar">?</div>
      <div><span id="userName">...</span><small id="userRole">...</small></div>
    </div>
    <button class="logout-btn" onclick="logout()">🚪 Cerrar sesión</button>
  </div>
</aside>

<main class="main">

  <!-- DASHBOARD -->
  <div class="page active" id="page-dashboard">
    <div class="page-title">Dashboard</div>
    <div class="page-sub">Resumen general de Hugo's Solutions</div>
    <div class="stats-row">
      <div class="stat-card"><div class="label">Total mensajes</div><div class="val blue" id="s-total">-</div><div class="hint">Formulario contacto</div></div>
      <div class="stat-card"><div class="label">Sin leer</div><div class="val yellow" id="s-unread">-</div><div class="hint">Pendientes</div></div>
      <div class="stat-card"><div class="label">Leídos</div><div class="val green" id="s-read">-</div><div class="hint">Atendidos</div></div>
      <div class="stat-card"><div class="label">Chats abiertos</div><div class="val red" id="s-chats">-</div><div class="hint">En tiempo real</div></div>
    </div>
    <div class="chart-card"><h3>📈 Mensajes por servicio</h3><div id="chart-bars"></div></div>
  </div>

  <!-- MENSAJES -->
  <div class="page" id="page-messages">
    <div class="page-title">Mensajes del formulario</div>
    <div class="page-sub">Solicitudes recibidas desde la web</div>
    <div class="msg-filters">
      <div class="filter-btn active" onclick="filterMsgs('all',this)">Todos</div>
      <div class="filter-btn" onclick="filterMsgs('unread',this)">Sin leer</div>
      <div class="filter-btn" onclick="filterMsgs('read',this)">Leídos</div>
    </div>
    <div class="msg-list" id="msg-list"></div>
  </div>

  <!-- CHAT EN VIVO -->
  <div class="page" id="page-chat">
    <div class="page-title">Chat en vivo</div>
    <div class="page-sub">Conversaciones en tiempo real con clientes</div>
    <div class="chat-layout">
      <div class="chat-list">
        <div class="chat-list-head">💬 Sesiones activas</div>
        <div id="sessionList"></div>
      </div>
      <div class="chat-window" id="chatWindow">
        <div class="no-chat">← Selecciona una conversación</div>
      </div>
    </div>
  </div>

  <!-- EMPLEADOS (admin) -->
  <div class="page admin-only" id="page-employees">
    <div class="page-title">Gestión de empleados</div>
    <div class="page-sub">Añadir, eliminar y cambiar contraseñas</div>
    <div class="emp-table-card">
      <table class="emp-table">
        <thead><tr><th>Nombre</th><th>Email</th><th>Rol</th><th>Acción</th></tr></thead>
        <tbody id="emp-tbody"></tbody>
      </table>
    </div>
    <div class="two-col">
      <div class="form-block">
        <h3>➕ Añadir empleado</h3>
        <div class="fg"><label>Nombre</label><input id="e-name" placeholder="Nombre completo"/></div>
        <div class="fg"><label>Email</label><input id="e-email" type="email" placeholder="email@hugos.com"/></div>
        <div class="fg"><label>Contraseña</label><input id="e-pass" type="password" placeholder="Mínimo 8 caracteres"/></div>
        <div class="fg"><label>Rol</label><select id="e-role"><option value="employee">Empleado</option><option value="admin">Admin</option></select></div>
        <button class="action-btn" onclick="addEmployee()">Crear empleado</button>
      </div>
      <div class="form-block">
        <h3>🔑 Cambiar contraseña</h3>
        <div class="fg"><label>Empleado</label><select id="pw-emp"><option value="">Selecciona...</option></select></div>
        <div class="fg"><label>Nueva contraseña</label><input id="pw-new" type="password" placeholder="Nueva contraseña"/></div>
        <div class="fg"><label>Confirmar</label><input id="pw-confirm" type="password" placeholder="Repite la contraseña"/></div>
        <button class="action-btn" onclick="changePassword()">Cambiar contraseña</button>
      </div>
    </div>
  </div>

</main>

<div class="toast-p" id="toastP"></div>

<script>
const socket = io();
let currentUser = null;
let allMessages = [];
let allSessions = [];
let activeSessionId = null;

async function init() {
  const r = await fetch('/api/me');
  if (!r.ok) { window.location.href='/login'; return; }
  currentUser = await r.json();
  document.getElementById('userName').textContent = currentUser.name;
  document.getElementById('userRole').textContent = currentUser.role==='admin' ? '⭐ Admin' : 'Empleado';
  document.getElementById('userAvatar').textContent = currentUser.name.charAt(0).toUpperCase();
  if (currentUser.role === 'admin') {
    document.querySelectorAll('.admin-only').forEach(el => { el.style.display='flex'; });
    document.getElementById('page-employees').style.display='none';
  }
  socket.emit('employee_join');
  loadStats(); loadMessages(); loadSessions();
  if (currentUser.role==='admin') loadEmployees();
}

function showPage(name) {
  document.querySelectorAll('.page').forEach(p=>p.classList.remove('active'));
  document.querySelectorAll('.sb-item').forEach(i=>i.classList.remove('active'));
  document.getElementById('page-'+name).classList.add('active');
  const nav = document.getElementById('nav-'+name);
  if (nav) nav.classList.add('active');
  if (name==='dashboard') document.querySelector('.sb-item').classList.add('active');
  if (name==='chat') document.getElementById('badge-chat').style.display='none';
}

// ── STATS ───────────────────────────────────
async function loadStats() {
  const r = await fetch('/api/stats'); const d = await r.json();
  document.getElementById('s-total').textContent  = d.total;
  document.getElementById('s-unread').textContent = d.unread;
  document.getElementById('s-read').textContent   = d.read;
  document.getElementById('s-chats').textContent  = d.openChats;
  const badge = document.getElementById('badge-unread');
  if (d.unread>0){badge.textContent=d.unread;badge.style.display='inline';}
  else badge.style.display='none';
  const max = d.byService[0]?.c||1;
  document.getElementById('chart-bars').innerHTML = d.byService.map(s=>`
    <div class="bar-row">
      <div class="bar-label">${s.service||'Sin especificar'}</div>
      <div class="bar-track"><div class="bar-fill" style="width:${(s.c/max*100).toFixed(0)}%"></div></div>
      <div class="bar-count">${s.c}</div>
    </div>`).join('')||'<div class="empty">Sin datos</div>';
}

// ── MENSAJES ────────────────────────────────
async function loadMessages() {
  const r = await fetch('/api/messages');
  allMessages = await r.json();
  renderMessages('all');
}
function renderMessages(filter) {
  const list = filter==='all' ? allMessages : allMessages.filter(m=>m.status===filter);
  const isAdmin = currentUser?.role==='admin';
  document.getElementById('msg-list').innerHTML = list.length ? list.map(m=>`
    <div class="msg-card ${m.status}" id="mc-${m.id}">
      <div class="msg-head">
        <span class="status-dot ${m.status==='unread'?'dot-unread':'dot-read'}"></span>
        <span class="msg-name">${m.name}</span>
        <span class="msg-email-tag">✉ ${m.email}</span>
        ${m.service?`<span class="msg-service">${m.service}</span>`:''}
        <span class="msg-date">${m.created_at}</span>
      </div>
      <div class="msg-body">${m.message}</div>
      <div class="msg-actions">
        ${m.status==='unread'
          ?`<button class="act-btn act-read" onclick="setStatus(${m.id},'read')">✓ Marcar leído</button>`
          :`<button class="act-btn act-unread" onclick="setStatus(${m.id},'unread')">↩ Sin leer</button>`}
        ${isAdmin?`<button class="act-btn act-del" onclick="deleteMsg(${m.id})">🗑 Eliminar</button>`:''}
      </div>
    </div>`).join('') : '<div class="empty">No hay mensajes en esta categoría</div>';
}
function filterMsgs(f,btn){
  document.querySelectorAll('.filter-btn').forEach(b=>b.classList.remove('active'));
  btn.classList.add('active'); renderMessages(f);
}
async function setStatus(id,status){
  await fetch(`/api/messages/${id}/status`,{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({status})});
  allMessages=allMessages.map(m=>m.id===id?{...m,status}:m);
  loadStats(); renderMessages('all');
}
async function deleteMsg(id){
  if(!confirm('¿Eliminar?'))return;
  await fetch(`/api/messages/${id}`,{method:'DELETE'});
  allMessages=allMessages.filter(m=>m.id!==id);
  loadStats(); renderMessages('all');
}

// ── CHAT ─────────────────────────────────────
async function loadSessions() {
  const r = await fetch('/api/chats');
  allSessions = await r.json();
  renderSessionList();
}
function renderSessionList() {
  const el = document.getElementById('sessionList');
  if (!allSessions.length){el.innerHTML='<div class="empty">Sin conversaciones</div>';return;}
  el.innerHTML = allSessions.map(s=>`
    <div class="chat-session ${activeSessionId===s.id?'active':''}" onclick="openSession(${s.id})">
      <h4><span class="cs-status ${s.status==='open'?'cs-open':'cs-closed'}"></span>${s.client_name}</h4>
      <div class="cs-email">✉ ${s.client_email}</div>
      <div class="cs-cart">${formatCart(s.cart)}</div>
      <div class="cs-time">${s.created_at}</div>
    </div>`).join('');
}
function formatCart(cartJson) {
  try { const c=JSON.parse(cartJson); return c.map(i=>i.name).join(', ')||'Sin servicios'; } catch{return '';}
}
async function openSession(id) {
  activeSessionId = id;
  socket.emit('join_session', id);
  renderSessionList();
  const sess = allSessions.find(s=>s.id===id);
  const msgs = await fetch(`/api/chats/${id}/messages`).then(r=>r.json());
  const isClosed = sess.status==='closed';
  document.getElementById('chatWindow').innerHTML = `
    <div class="chat-win-head">
      <div>
        <h3>${sess.client_name} <span class="cs-status ${sess.status==='open'?'cs-open':'cs-closed'}"></span></h3>
        <p>✉ ${sess.client_email} · ${formatCart(sess.cart)}</p>
      </div>
      ${!isClosed?`<button class="close-chat-btn" onclick="closeSession(${id})">✕ Cerrar chat</button>`:'<span style="color:var(--muted);font-size:.78rem">Chat cerrado</span>'}
    </div>
    <div class="chat-msgs-panel" id="panelMsgs">
      ${msgs.map(m=>`<div class="msg-bubble ${m.sender}"><div class="sender">${m.sender_name}</div>${m.message}<div class="mtime">${m.created_at}</div></div>`).join('')}
    </div>
    ${!isClosed?`<div class="chat-reply">
      <input id="replyInput" placeholder="Escribe tu respuesta..." onkeydown="if(event.key==='Enter')sendReply(${id})"/>
      <button onclick="sendReply(${id})">Enviar</button>
    </div>`:'<div style="padding:.7rem 1rem;color:var(--muted);font-size:.82rem;border-top:1px solid var(--border);text-align:center">Chat cerrado</div>'}`;
  const pm = document.getElementById('panelMsgs');
  if(pm) pm.scrollTop = pm.scrollHeight;
}
function sendReply(sessionId) {
  const inp = document.getElementById('replyInput');
  const msg = inp.value.trim();
  if(!msg) return;
  socket.emit('send_message',{sessionId,message:msg});
  inp.value='';
}
async function closeSession(id) {
  if(!confirm('¿Cerrar este chat?'))return;
  await fetch(`/api/chats/${id}/close`,{method:'PATCH'});
  allSessions = allSessions.map(s=>s.id===id?{...s,status:'closed'}:s);
  openSession(id); renderSessionList(); loadStats();
}
// Socket events
socket.on('new_chat', (sess) => {
  allSessions.unshift(sess);
  renderSessionList();
  document.getElementById('badge-chat').style.display='inline';
  showToast('💬 Nuevo chat de '+sess.client_name, false);
  loadStats();
});
socket.on('new_message', (msg) => {
  const pm = document.getElementById('panelMsgs');
  if(pm) {
    pm.innerHTML += `<div class="msg-bubble ${msg.sender}"><div class="sender">${msg.sender_name}</div>${msg.message}<div class="mtime">${msg.created_at}</div></div>`;
    pm.scrollTop = pm.scrollHeight;
  }
});
socket.on('chat_activity', ({sessionId}) => {
  if (sessionId !== activeSessionId) {
    document.getElementById('badge-chat').style.display='inline';
  }
});

// ── EMPLEADOS ───────────────────────────────
async function loadEmployees() {
  const r = await fetch('/api/employees');
  const emps = await r.json();
  // tabla
  document.getElementById('emp-tbody').innerHTML = emps.map(e=>`
    <tr>
      <td>${e.name}</td>
      <td style="color:var(--muted);font-family:monospace;font-size:.8rem">${e.email}</td>
      <td><span class="role-badge ${e.role==='admin'?'role-admin':'role-employee'}">${e.role==='admin'?'⭐ Admin':'Empleado'}</span></td>
      <td>${e.id!==currentUser.id?`<button class="act-btn act-del" onclick="deleteEmp(${e.id})">🗑</button>`:'-'}</td>
    </tr>`).join('');
  // select cambio contraseña
  const sel = document.getElementById('pw-emp');
  sel.innerHTML = '<option value="">Selecciona empleado...</option>' + emps.map(e=>`<option value="${e.id}">${e.name} (${e.email})</option>`).join('');
}
async function addEmployee() {
  const name=document.getElementById('e-name').value.trim();
  const email=document.getElementById('e-email').value.trim();
  const password=document.getElementById('e-pass').value;
  const role=document.getElementById('e-role').value;
  if(!name||!email||!password){showToast('Rellena todos los campos',true);return}
  const r=await fetch('/api/employees',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,email,password,role})});
  if(r.ok){showToast('✓ Empleado creado');document.getElementById('e-name').value='';document.getElementById('e-email').value='';document.getElementById('e-pass').value='';loadEmployees();}
  else{const d=await r.json();showToast(d.error,true);}
}
async function deleteEmp(id){
  if(!confirm('¿Eliminar empleado?'))return;
  await fetch(`/api/employees/${id}`,{method:'DELETE'});
  showToast('✓ Empleado eliminado'); loadEmployees();
}
async function changePassword(){
  const empId=document.getElementById('pw-emp').value;
  const newPass=document.getElementById('pw-new').value;
  const confirm2=document.getElementById('pw-confirm').value;
  if(!empId||!newPass){showToast('Selecciona empleado y nueva contraseña',true);return}
  if(newPass!==confirm2){showToast('Las contraseñas no coinciden',true);return}
  if(newPass.length<6){showToast('Mínimo 6 caracteres',true);return}
  const r=await fetch(`/api/employees/${empId}/password`,{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({newPassword:newPass})});
  if(r.ok){showToast('✓ Contraseña cambiada');document.getElementById('pw-new').value='';document.getElementById('pw-confirm').value='';document.getElementById('pw-emp').value='';}
  else{const d=await r.json();showToast(d.error,true);}
}

async function logout(){await fetch('/api/logout',{method:'POST'});window.location.href='/';}

function showToast(msg,isErr=false){
  const t=document.getElementById('toastP');
  t.textContent=msg; t.className='toast-p'+(isErr?' err':'');
  t.style.display='block'; setTimeout(()=>t.style.display='none',3500);
}

init();
</script>
</body>
</html>
PANELEOF
ok "panel.html generado"

# ══════════════════════════════════════════════
step "Configurando Nginx..."
cat > /etc/nginx/sites-available/hugos-solutions << 'NGINXCONF'
server {
    listen 80;
    server_name localhost;
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
NGINXCONF
ln -sf /etc/nginx/sites-available/hugos-solutions /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
(nginx -t > /dev/null 2>&1 && systemctl restart nginx > /dev/null 2>&1) & spinner $! "Nginx"
ok "Nginx activo"

step "Instalando PM2 y arrancando..."
(npm install -g pm2 > /dev/null 2>&1) & spinner $! "PM2"
cd "$PROJECT_DIR"
pm2 stop hugos-solutions > /dev/null 2>&1; pm2 delete hugos-solutions > /dev/null 2>&1
pm2 start server.js --name "hugos-solutions" > /dev/null 2>&1
pm2 save > /dev/null 2>&1; pm2 startup systemd -u root --hp /root > /dev/null 2>&1
ok "Web arrancada con PM2"

# ══════════════════════════════════════════════
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  ✦ ¡v4.0 instalada! ✦${RESET}\n"
echo -e "  ${WHITE}🌐  Web pública:${RESET}  ${CYAN}http://localhost${RESET}"
echo -e "  ${WHITE}🔒  Login panel:${RESET}  ${CYAN}http://localhost/login${RESET}"
echo -e "  ${WHITE}📊  Panel:${RESET}        ${CYAN}http://localhost/panel${RESET}\n"
echo -e "  ${YELLOW}Credenciales:${RESET}"
echo -e "  Admin →    ${WHITE}admin@hugos.com${RESET}    /  ${WHITE}admin1234${RESET}"
echo -e "  Empleado → ${WHITE}ana@hugos.com${RESET}      /  ${WHITE}empleado1234${RESET}\n"
echo -e "  ${RED}⚠️  Cambia las contraseñas desde el panel → Empleados${RESET}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
