// Generador de carga para la prueba del HPA: peticiones concurrentes a la API vía Ingress.
// Uso: node scripts/load-test.js <segundos> <concurrencia>
const http = require('http');
const [secs = 180, conc = 64] = process.argv.slice(2).map(Number);
const agent = new http.Agent({ keepAlive: true, maxSockets: conc });
const end = Date.now() + secs * 1000;
let ok = 0, fail = 0;
function hit() {
  if (Date.now() > end) return;
  http.get('http://localhost/api/productos', { agent }, (res) => {
    res.resume();
    res.statusCode === 200 ? ok++ : fail++;
    hit();
  }).on('error', () => { fail++; setTimeout(hit, 100); });
}
for (let i = 0; i < conc; i++) hit();
const t = setInterval(() => console.log(`peticiones OK=${ok} fallidas=${fail}`), 30000);
setTimeout(() => { clearInterval(t); console.log(`FIN: OK=${ok} fallidas=${fail}`); process.exit(0); }, secs * 1000 + 500);
