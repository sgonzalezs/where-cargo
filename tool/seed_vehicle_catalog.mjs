// Publica assets/data/vehicle_catalog.json en Firestore:
//   vehicle_brands/{brandId}  { name }
//   vehicle_models/{modelId}  { brand_id, name, variants: { <id>: {...} } }
//   catalog_meta/vehicles     { version }  ← se escribe al final
//
// Para publicar cambios: editar el JSON, SUBIR "version" y ejecutar el
// script. La app compara esa versión con la suya y, si es mayor, descarga el
// catálogo; sin cambiar la versión los usuarios no reciben los cambios.
//
// Las reglas no permiten escribir el catálogo desde la app, así que se usa la
// sesión de Firebase CLI (`firebase login`) de un administrador del proyecto.
// Ejecutar ANTES de publicar una versión de la app con modelos nuevos: las
// reglas rechazan vehículos cuyo model_id/variant_id no exista en Firestore.
//
//   node tool/seed_vehicle_catalog.mjs [--dry-run] [--force]
//
// Solo crea o actualiza; nunca borra modelos (pueden tener vehículos que los
// referencian).

import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { join } from 'node:path';

const PROJECT_ID = 'where-cargo';
const dryRun = process.argv.includes('--dry-run');

const catalog = JSON.parse(
  readFileSync(new URL('../assets/data/vehicle_catalog.json', import.meta.url), 'utf8'),
);

const docs = [
  ...catalog.brands.map((b) => ({
    path: `vehicle_brands/${b.id}`,
    fields: { name: b.name, catalog_version: catalog.version },
  })),
  ...catalog.models.map((m) => ({
    path: `vehicle_models/${m.id}`,
    fields: {
      brand_id: m.brand_id,
      name: m.name,
      catalog_version: catalog.version,
      variants: Object.fromEntries(
        m.variants.map(({ id, ...spec }, order) => [id, { ...spec, order }]),
      ),
    },
  })),
];

const brandIds = new Set(catalog.brands.map((b) => b.id));
for (const m of catalog.models) {
  if (!brandIds.has(m.brand_id)) throw new Error(`${m.id}: marca ${m.brand_id} no existe`);
}

console.log(`Catálogo v${catalog.version}: ${catalog.brands.length} marcas, ${catalog.models.length} modelos`);
if (dryRun) process.exit(0);

// Token de la sesión de Firebase CLI
const require = createRequire(import.meta.url);
const toolsRoot = join(execSync('npm root -g').toString().trim(), 'firebase-tools');
const apiv2 = require(join(toolsRoot, 'lib', 'apiv2.js'));
const config = JSON.parse(
  readFileSync(join(homedir(), '.config', 'configstore', 'firebase-tools.json'), 'utf8'),
);
const refreshToken = config.tokens?.refresh_token;
if (!refreshToken) throw new Error('Inicia sesión primero con: firebase login');
apiv2.setRefreshToken(refreshToken);
const accessToken = await apiv2.getAccessToken();

function toValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (Array.isArray(value)) return { arrayValue: { values: value.map(toValue) } };
  return {
    mapValue: {
      fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, toValue(v)])),
    },
  };
}

const base = `projects/${PROJECT_ID}/databases/(default)/documents`;
const headers = {
  Authorization: `Bearer ${accessToken}`,
  'Content-Type': 'application/json',
  'x-goog-user-project': PROJECT_ID,
};

const metaRes = await fetch(`https://firestore.googleapis.com/v1/${base}/catalog_meta/vehicles`, { headers });
if (metaRes.ok) {
  const published = Number((await metaRes.json()).fields?.version?.integerValue ?? 0);
  if (published >= catalog.version && !process.argv.includes('--force')) {
    console.error(
      `Firestore ya tiene la versión ${published}. Sube "version" en el JSON ` +
        '(o usa --force para reescribir la misma versión).',
    );
    process.exit(1);
  }
} else if (metaRes.status !== 404) {
  throw new Error(`Firestore ${metaRes.status}: ${await metaRes.text()}`);
}

// La versión va al final: la app solo descarga cuando todo está publicado
docs.push({
  path: 'catalog_meta/vehicles',
  fields: { version: catalog.version, updated_at: new Date().toISOString() },
});
// commit admite hasta 500 escrituras por llamada
for (let i = 0; i < docs.length; i += 500) {
  const writes = docs.slice(i, i + 500).map((d) => ({
    update: {
      name: `${base}/${d.path}`,
      fields: Object.fromEntries(Object.entries(d.fields).map(([k, v]) => [k, toValue(v)])),
    },
  }));
  const res = await fetch(`https://firestore.googleapis.com/v1/${base}:commit`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ writes }),
  });
  if (!res.ok) throw new Error(`Firestore ${res.status}: ${await res.text()}`);
}
console.log(`Publicados ${docs.length} documentos en ${PROJECT_ID}`);
