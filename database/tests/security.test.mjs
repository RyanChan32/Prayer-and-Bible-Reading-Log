// Runs the real schema and security rules in an in-memory Postgres.
// Supabase's auth schema is stubbed with the minimum those files rely on.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const sql = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const db = new PGlite();

await db.exec(`
  create role anon nologin;
  create role authenticated nologin;
  create schema auth;
  grant usage on schema auth to anon, authenticated;
  create table auth.users (id uuid primary key default gen_random_uuid(), email text unique, raw_user_meta_data jsonb);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
`);
await db.exec(sql('../migrations/0001_schema.sql'));
await db.exec(sql('../policies/0001_row_level_security.sql'));

async function newUser(name, email) {
  const r = await db.query(
    `insert into auth.users (email, raw_user_meta_data) values ($1, $2) returning id`,
    [email, JSON.stringify({ name })]
  );
  return r.rows[0].id;
}
async function as(uid, text, params = []) {
  await db.exec(`reset role; select set_config('test.uid', '${uid ?? ''}', false); set role ${uid ? 'authenticated' : 'anon'};`);
  try { return (await db.query(text, params)).rows; }
  finally { await db.exec('reset role'); }
}
const denied = (uid, text, params) => assert.rejects(as(uid, text, params));

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`ok - ${name}`);
}

const ann = await newUser('Ann', 'ann@example.test');
const ben = await newUser('Ben', 'ben@example.test');
const cam = await newUser('Cam', 'cam@example.test');
const dee = await newUser('', 'dee@example.test');

await test('sign-up creates a profile, falling back to the email name', async () => {
  const rows = await as(ann, 'select display_name from profiles order by display_name');
  assert.deepEqual(rows.map(r => r.display_name), ['Ann', 'Ben', 'Cam', 'dee']);
});

await test('signed-out visitors can read nothing', async () => {
  for (const t of ['profiles', 'prayers', 'readings', 'groups', 'group_members', 'messages', 'message_praying']) {
    await denied(null, `select * from ${t}`);
  }
  await denied(null, `select create_group('x')`);
});

await test('users can only edit their own profile', async () => {
  await as(ann, `update profiles set display_name = 'Hacked' where id = $1`, [ben]);
  const [b] = await as(ben, 'select display_name from profiles where id = $1', [ben]);
  assert.equal(b.display_name, 'Ben');
});

await test('private prayers stay private; public ones are visible', async () => {
  await as(ann, `insert into prayers (text) values ('private')`);
  await as(ann, `insert into prayers (text, is_public) values ('public', true)`);
  assert.equal((await as(ann, 'select * from prayers')).length, 2);
  assert.deepEqual((await as(ben, 'select text from prayers')).map(r => r.text), ['public']);
});

await test("users can't add, change or delete someone else's prayers", async () => {
  await denied(ben, `insert into prayers (user_id, text) values ($1, 'forged')`, [ann]);
  await as(ben, `update prayers set text = 'changed' where is_public`);
  await as(ben, `delete from prayers where is_public`);
  assert.deepEqual((await as(ann, 'select text from prayers where is_public')).map(r => r.text), ['public']);
  await denied(ann, `update prayers set user_id = $1 where is_public`, [ben]);
});

await test('private readings stay private', async () => {
  await as(ann, `insert into readings (book, chapter) values ('John', 3)`);
  assert.equal((await as(ben, 'select * from readings')).length, 0);
  assert.equal((await as(ann, 'select * from readings')).length, 1);
});

const [{ create_group: group }] = await as(ann, `select create_group('Friday Prayer', 'desc')`);

await test('creating a group makes you its owner; outsiders see nothing', async () => {
  const [m] = await as(ann, 'select role from group_members where group_id = $1', [group]);
  assert.equal(m.role, 'owner');
  assert.equal((await as(ben, 'select * from groups')).length, 0);
  assert.equal((await as(ben, 'select * from group_members')).length, 0);
  assert.equal((await as(ben, 'select * from messages')).length, 0);
});

await test('roles and memberships cannot be changed directly', async () => {
  await denied(ben, `insert into group_members (group_id, user_id, role) values ($1, $2, 'owner')`, [group, ben]);
  await denied(ann, `update group_members set role = 'admin' where group_id = $1`, [group]);
  await denied(ann, `delete from group_members where group_id = $1`, [group]);
  await denied(ann, `insert into groups (name, owner_id) values ('x', $1)`, [ann]);
  await denied(ann, `update groups set owner_id = $1 where id = $2`, [ben, group]);
  await denied(ann, `update groups set members_can_invite = true where id = $1`, [group]);
});

await test('only permitted people can add members', async () => {
  await denied(ben, 'select add_group_member($1, $2)', [group, 'ben@example.test']);
  await denied(ann, 'select add_group_member($1, $2)', [group, 'nobody@example.test']);
  const [r] = await as(ann, 'select add_group_member($1, $2)', [group, 'BEN@example.test']);
  assert.equal(r.add_group_member, 'Ben');
  await denied(ann, 'select add_group_member($1, $2)', [group, 'ben@example.test']);
  await denied(ben, 'select add_group_member($1, $2)', [group, 'cam@example.test']);
  await as(ann, 'select set_group_settings($1, true, true)', [group]);
  await as(ben, 'select add_group_member($1, $2)', [group, 'cam@example.test']);
  await as(ann, 'select set_group_settings($1, false, false)', [group]);
});

await test('members can chat; sharing and system messages are restricted', async () => {
  await as(ben, `insert into messages (group_id, text) values ($1, 'hello')`, [group]);
  await denied(ben, `insert into messages (group_id, type, text) values ($1, 'system', 'fake')`, [group]);
  await denied(ben, `insert into messages (group_id, type, prayer) values ($1, 'prayer', '{}')`, [group]);
  await denied(ben, `insert into messages (group_id, user_id, text) values ($1, $2, 'as ann')`, [group, ann]);
  await denied(dee, `insert into messages (group_id, text) values ($1, 'outsider')`, [group]);
  await as(ann, 'select set_group_settings($1, false, true)', [group]);
  await as(ben, `insert into messages (group_id, type, prayer) values ($1, 'prayer', '{"text":"pray"}')`, [group]);
});

await test('praying reactions are limited to members, as themselves', async () => {
  const [m] = await as(ben, `select id from messages where type = 'prayer'`);
  await as(cam, 'insert into message_praying (message_id) values ($1)', [m.id]);
  await denied(dee, 'insert into message_praying (message_id) values ($1)', [m.id]);
  await denied(cam, 'insert into message_praying (message_id, user_id) values ($1, $2)', [m.id, ann]);
  assert.equal((await as(dee, 'select * from message_praying')).length, 0);
});

await test('only the owner manages roles; admins edit details but not settings', async () => {
  await denied(ben, 'select set_member_role($1, $2, $3)', [group, ben, 'admin']);
  await denied(ben, 'select set_group_settings($1, true, true)', [group]);
  await as(ann, 'select set_member_role($1, $2, $3)', [group, ben, 'admin']);
  await denied(ann, 'select set_member_role($1, $2, $3)', [group, ben, 'owner']);
  await denied(ben, 'select set_group_settings($1, true, true)', [group]);
  await as(ben, `update groups set name = 'Renamed' where id = $1`, [group]);
  await as(cam, `update groups set name = 'By member' where id = $1`, [group]);
  assert.equal((await as(ann, 'select name from groups where id = $1', [group]))[0].name, 'Renamed');
  await as(ben, 'delete from groups where id = $1', [group]);
  assert.equal((await as(ann, 'select * from groups where id = $1', [group])).length, 1);
});

await test('removal rules: admins remove members only; owners must transfer to leave', async () => {
  await denied(cam, 'select remove_group_member($1, $2)', [group, ben]);
  await denied(ben, 'select remove_group_member($1, $2)', [group, ann]);
  await denied(ann, 'select remove_group_member($1, $2)', [group, ann]);
  await as(ben, 'select remove_group_member($1, $2)', [group, cam]);
  assert.equal((await as(cam, 'select * from groups')).length, 0);
  assert.equal((await as(cam, 'select * from messages')).length, 0);
});

await test('ownership transfers cleanly, and the new owner can delete the group', async () => {
  await denied(ben, 'select transfer_group_ownership($1, $2)', [group, ben]);
  await denied(ann, 'select transfer_group_ownership($1, $2)', [group, cam]);
  await as(ann, 'select transfer_group_ownership($1, $2)', [group, ben]);
  const roles = await as(ann, 'select user_id, role from group_members where group_id = $1', [group]);
  assert.equal(roles.find(r => r.user_id === ann).role, 'admin');
  assert.equal(roles.find(r => r.user_id === ben).role, 'owner');
  await as(ann, 'select remove_group_member($1, $2)', [group, ann]);
  await as(ben, 'delete from groups where id = $1', [group]);
  assert.equal((await as(ben, 'select * from messages')).length, 0);
});

await test('deleting an account removes its data', async () => {
  await db.query('delete from auth.users where id = $1', [ann]);
  const left = await db.query('select count(*)::int as n from prayers');
  assert.equal(left.rows[0].n, 0);
});

console.log(`\n${passed} tests passed`);
await db.close();
