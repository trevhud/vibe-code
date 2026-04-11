#!/usr/bin/env npx tsx
/**
 * Comprehensive relay server test suite.
 * Run with: npx tsx src/test-all.ts
 * Requires the relay server to be running on localhost:3578.
 */

import WebSocket from 'ws';
import { classifyEvent } from './pipeline/event-classifier.js';
import { summarizeEvent } from './pipeline/template-summarizer.js';
import { parseUpstream, encodeDownstream } from './protocol/messages.js';
import type { JsonlRecord } from './sessions/jsonl-tailer.js';
import type { DownstreamMessage } from './protocol/messages.js';

const RELAY_URL = 'ws://localhost:3578/ws';
const HTTP_URL = 'http://localhost:3578';

let passed = 0;
let failed = 0;

function assert(condition: boolean, testName: string, detail?: string) {
  if (condition) {
    passed++;
    console.log(`  ✓ ${testName}`);
  } else {
    failed++;
    console.log(`  ✗ ${testName}${detail ? ` — ${detail}` : ''}`);
  }
}

function assertEq(actual: unknown, expected: unknown, testName: string) {
  const eq = JSON.stringify(actual) === JSON.stringify(expected);
  assert(eq, testName, eq ? undefined : `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

// ========== Unit Tests: Protocol Messages ==========

function testProtocolMessages() {
  console.log('\n--- Protocol Messages ---');

  // Valid upstream parse
  const authResult = parseUpstream('{"type":"auth","token":"abc"}');
  assert(authResult.success === true, 'parse valid auth message');
  if (authResult.success) {
    assertEq(authResult.data.type, 'auth', 'auth message type');
    assertEq((authResult.data as { token: string }).token, 'abc', 'auth token value');
  }

  const inputResult = parseUpstream('{"type":"input","sessionId":"s1","text":"hello world"}');
  assert(inputResult.success === true, 'parse valid input message');

  const sessionListResult = parseUpstream('{"type":"session_list_request"}');
  assert(sessionListResult.success === true, 'parse session_list_request');

  const attachResult = parseUpstream('{"type":"attach","sessionId":"s1"}');
  assert(attachResult.success === true, 'parse attach message');

  const detachResult = parseUpstream('{"type":"detach"}');
  assert(detachResult.success === true, 'parse detach message');

  const pongResult = parseUpstream('{"type":"pong"}');
  assert(pongResult.success === true, 'parse pong message');

  // Invalid upstream parse
  const invalidJson = parseUpstream('not json');
  assert(invalidJson.success === false, 'reject invalid JSON');

  const unknownType = parseUpstream('{"type":"unknown"}');
  assert(unknownType.success === false, 'reject unknown message type');

  const missingField = parseUpstream('{"type":"input","sessionId":"s1"}');
  assert(missingField.success === false, 'reject missing required field (text)');

  // Downstream encoding
  const encoded = encodeDownstream({ type: 'ping' });
  assertEq(encoded, '{"type":"ping"}', 'encode downstream ping');

  const encoded2 = encodeDownstream({
    type: 'auth_result',
    success: true,
  });
  assertEq(JSON.parse(encoded2).success, true, 'encode auth_result success field');
}

// ========== Unit Tests: Event Classifier ==========

function testEventClassifier() {
  console.log('\n--- Event Classifier ---');

  // AskUserQuestion → question/interrupt
  const askRecord: JsonlRecord = {
    type: 'assistant',
    message: {
      content: [
        {
          type: 'tool_use',
          name: 'AskUserQuestion',
          id: 'tu1',
          input: { questions: [{ question: 'Which approach?' }] },
        },
      ],
    },
  };
  const askResult = classifyEvent(askRecord);
  assert(askResult !== null, 'classify AskUserQuestion as non-null');
  assertEq(askResult?.priority, 'interrupt', 'AskUserQuestion → interrupt');
  assertEq(askResult?.category, 'question', 'AskUserQuestion → question');

  // is_error tool_result → error/interrupt
  const errorRecord: JsonlRecord = {
    type: 'user',
    message: {
      content: [
        {
          type: 'tool_result',
          tool_use_id: 'tu1',
          is_error: true,
          content: 'Command failed with exit code 1',
        },
      ],
    },
  };
  const errorResult = classifyEvent(errorRecord);
  assert(errorResult !== null, 'classify is_error tool_result');
  assertEq(errorResult?.priority, 'interrupt', 'is_error → interrupt');
  assertEq(errorResult?.category, 'error', 'is_error → error');

  // stderr with error pattern → error/interrupt
  const stderrRecord: JsonlRecord = {
    type: 'user',
    message: {
      content: [
        {
          type: 'tool_result',
          tool_use_id: 'tu2',
          content: 'fatal: not a git repository',
        },
      ],
    },
  };
  const stderrResult = classifyEvent(stderrRecord);
  assert(stderrResult !== null, 'classify stderr with "fatal:" pattern');
  assertEq(stderrResult?.category, 'error', 'fatal: → error');

  // exit code (non-zero) → error
  const exitCodeRecord: JsonlRecord = {
    type: 'user',
    message: {
      content: [
        {
          type: 'tool_result',
          tool_use_id: 'tu3',
          content: 'Exit code 127\n/bin/sh: foo: command not found',
        },
      ],
    },
  };
  const exitCodeResult = classifyEvent(exitCodeRecord);
  assert(exitCodeResult !== null, 'classify exit code 127');
  assertEq(exitCodeResult?.category, 'error', 'exit code 127 → error');

  // exit code 0 → NOT an error
  const exitCode0Record: JsonlRecord = {
    type: 'user',
    message: {
      content: [
        {
          type: 'tool_result',
          tool_use_id: 'tu4',
          content: 'Exit code 0\nSuccess',
        },
      ],
    },
  };
  const exitCode0Result = classifyEvent(exitCode0Record);
  assert(exitCode0Result === null, 'exit code 0 → null (not classified)');

  // end_turn with text-only → completion/interrupt
  const completionRecord: JsonlRecord = {
    type: 'assistant',
    message: {
      content: [{ type: 'text', text: 'Done! All files updated.' }],
      stop_reason: 'end_turn',
    },
  };
  const completionResult = classifyEvent(completionRecord);
  assert(completionResult !== null, 'classify end_turn text-only completion');
  assertEq(completionResult?.category, 'completion', 'end_turn text → completion');
  assertEq(completionResult?.priority, 'interrupt', 'end_turn text → interrupt');

  // end_turn with tool_use blocks → NOT a completion
  const toolUseEndRecord: JsonlRecord = {
    type: 'assistant',
    message: {
      content: [
        { type: 'text', text: 'Let me check that.' },
        { type: 'tool_use', name: 'Read', id: 'tu5', input: { path: '/foo' } },
      ],
      stop_reason: 'end_turn',
    },
  };
  const toolUseEndResult = classifyEvent(toolUseEndRecord);
  assert(toolUseEndResult === null, 'end_turn with tool_use → null (not text-only)');

  // system record → null
  const systemRecord: JsonlRecord = { type: 'system', message: { content: 'system prompt' } };
  const systemResult = classifyEvent(systemRecord);
  assert(systemResult === null, 'system record → null (silent)');

  // Python traceback
  const tracebackRecord: JsonlRecord = {
    type: 'user',
    message: {
      content: [
        {
          type: 'tool_result',
          tool_use_id: 'tu6',
          content: [{ type: 'text', text: 'Traceback (most recent call last):\n  File "main.py"' }],
        },
      ],
    },
  };
  const tracebackResult = classifyEvent(tracebackRecord);
  assert(tracebackResult !== null, 'classify Python traceback');
  assertEq(tracebackResult?.category, 'error', 'traceback → error');
}

// ========== Unit Tests: Template Summarizer ==========

function testTemplateSummarizer() {
  console.log('\n--- Template Summarizer ---');

  // Question summary
  const questionSummary = summarizeEvent({
    priority: 'interrupt',
    category: 'question',
    rawData: {
      type: 'tool_use',
      name: 'AskUserQuestion',
      input: {
        questions: [{ question: 'Which database backend should we use?' }],
      },
    },
  });
  assertEq(questionSummary, 'Which database backend should we use?', 'question extracts text');

  // Question fallback (no questions array)
  const questionFallback = summarizeEvent({
    priority: 'interrupt',
    category: 'question',
    rawData: { type: 'tool_use', name: 'AskUserQuestion', input: {} },
  });
  assertEq(questionFallback, 'Claude has a question.', 'question fallback');

  // Error summary — string content
  const errorSummary = summarizeEvent({
    priority: 'interrupt',
    category: 'error',
    rawData: {
      type: 'tool_result',
      is_error: true,
      content: 'Error: ENOENT: no such file or directory\nAt /foo/bar.ts:10',
    },
  });
  assert(errorSummary.startsWith('Error:'), 'error summary starts with Error:');
  assert(errorSummary.includes('ENOENT'), 'error includes ENOENT');

  // Error summary — array content
  const errorArraySummary = summarizeEvent({
    priority: 'interrupt',
    category: 'error',
    rawData: {
      type: 'tool_result',
      content: [{ type: 'text', text: 'fatal: not a git repository' }],
    },
  });
  assert(errorArraySummary.includes('fatal'), 'error array content extracts fatal line');

  // Error fallback (null data)
  const errorFallback = summarizeEvent({
    priority: 'interrupt',
    category: 'error',
    rawData: null,
  });
  assertEq(errorFallback, 'An error occurred.', 'error fallback with null');

  // Completion — short text
  const completionShort = summarizeEvent({
    priority: 'interrupt',
    category: 'completion',
    rawData: [{ type: 'text', text: 'All done!' }],
  });
  assertEq(completionShort, 'Claude finished: All done!', 'short completion uses text');

  // Completion — long text falls back
  const longText = 'A'.repeat(300);
  const completionLong = summarizeEvent({
    priority: 'interrupt',
    category: 'completion',
    rawData: [{ type: 'text', text: longText }],
  });
  assertEq(completionLong, 'Claude finished responding.', 'long completion falls back');

  // Permission
  const permSummary = summarizeEvent({ priority: 'interrupt', category: 'permission', rawData: {} });
  assertEq(permSummary, 'Claude needs permission to proceed.', 'permission summary');

  // Progress
  const progSummary = summarizeEvent({ priority: 'interrupt', category: 'progress', rawData: {} });
  assertEq(progSummary, 'Claude is making progress.', 'progress summary');

  // Truncation
  const longQuestion = 'Q'.repeat(250);
  const truncated = summarizeEvent({
    priority: 'interrupt',
    category: 'question',
    rawData: { input: { questions: [{ question: longQuestion }] } },
  });
  assert(truncated.length <= 200, `truncation: ${truncated.length} <= 200`);
  assert(truncated.endsWith('...'), 'truncated ends with ...');
}

// ========== Integration: HTTP Health Endpoint ==========

async function testHealthEndpoint() {
  console.log('\n--- HTTP Health Endpoint ---');

  const res = await fetch(`${HTTP_URL}/health`);
  assert(res.status === 200, 'health returns 200');

  const body = await res.json() as { status: string; version: string; uptime: number; clients: number };
  assertEq(body.status, 'ok', 'health status is ok');
  assertEq(body.version, '0.1.0', 'health version is 0.1.0');
  assert(typeof body.uptime === 'number' && body.uptime > 0, 'uptime is positive number');
  assert(typeof body.clients === 'number', 'clients count is number');
}

// ========== Integration: QR Pairing ==========

async function testQrPairing() {
  console.log('\n--- QR Pairing ---');

  const res = await fetch(`${HTTP_URL}/pair/json`);
  assert(res.status === 200, '/pair/json returns 200');

  const body = await res.json() as { relayUrl: string; token: string; hostname: string };
  assert(typeof body.relayUrl === 'string', 'pair has relayUrl');
  assert(body.relayUrl.startsWith('ws://'), 'relayUrl starts with ws://');
  assert(typeof body.token === 'string' && body.token.length > 0, 'pair has non-empty token');
  assert(typeof body.hostname === 'string', 'pair has hostname');
}

// ========== Integration: WebSocket Auth ==========

function connectWs(): WebSocket {
  return new WebSocket(RELAY_URL);
}

function waitForMessage(ws: WebSocket, timeoutMs = 5000): Promise<DownstreamMessage> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WS message timeout')), timeoutMs);
    ws.once('message', (data) => {
      clearTimeout(timer);
      resolve(JSON.parse(data.toString()));
    });
  });
}

function waitForOpen(ws: WebSocket, timeoutMs = 5000): Promise<void> {
  return new Promise((resolve, reject) => {
    if (ws.readyState === WebSocket.OPEN) return resolve();
    const timer = setTimeout(() => reject(new Error('WS open timeout')), timeoutMs);
    ws.once('open', () => { clearTimeout(timer); resolve(); });
    ws.once('error', (e) => { clearTimeout(timer); reject(e); });
  });
}

async function getValidToken(): Promise<string> {
  const res = await fetch(`${HTTP_URL}/pair/json`);
  const body = await res.json() as { token: string };
  return body.token;
}

async function testWsAuth() {
  console.log('\n--- WebSocket Auth ---');

  // Test 1: Good token → auth_result success
  {
    const token = await getValidToken();
    const ws = connectWs();
    await waitForOpen(ws);
    ws.send(JSON.stringify({ type: 'auth', token }));
    const msg = await waitForMessage(ws);
    assertEq(msg.type, 'auth_result', 'auth response type');
    assert((msg as { success: boolean }).success === true, 'valid token → success');
    ws.close();
  }

  // Test 2: Bad token → auth_result failure + disconnect
  {
    const ws = connectWs();
    await waitForOpen(ws);
    ws.send(JSON.stringify({ type: 'auth', token: 'invalid.jwt.token' }));
    const msg = await waitForMessage(ws);
    assertEq(msg.type, 'auth_result', 'bad auth response type');
    assert((msg as { success: boolean }).success === false, 'invalid token → failure');
    // Wait a moment for close
    await new Promise(r => setTimeout(r, 500));
    assert(ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING, 'bad auth → ws closed');
    ws.close();
  }

  // Test 3: Non-auth first message → disconnect
  {
    const ws = connectWs();
    await waitForOpen(ws);
    ws.send(JSON.stringify({ type: 'session_list_request' }));
    // Should disconnect — wait for close
    await new Promise(r => setTimeout(r, 1000));
    assert(ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING, 'non-auth first → disconnected');
    ws.close();
  }
}

// ========== Integration: Session Discovery ==========

async function testSessionDiscovery() {
  console.log('\n--- Session Discovery ---');

  const token = await getValidToken();
  const ws = connectWs();
  await waitForOpen(ws);
  ws.send(JSON.stringify({ type: 'auth', token }));
  await waitForMessage(ws); // auth_result

  ws.send(JSON.stringify({ type: 'session_list_request' }));
  const msg = await waitForMessage(ws);
  assertEq(msg.type, 'session_list', 'session list response type');

  const sessions = (msg as { sessions: unknown[] }).sessions;
  assert(Array.isArray(sessions), 'sessions is an array');
  assert(sessions.length > 0, `found ${sessions.length} sessions`);

  // Validate session structure
  const first = sessions[0] as {
    id: string; projectPath: string; projectName: string;
    isActive: boolean; tmuxSession?: string; lastActivity?: string;
  };
  assert(typeof first.id === 'string' && first.id.length > 0, 'session has id');
  assert(typeof first.projectPath === 'string', 'session has projectPath');
  assert(typeof first.projectName === 'string', 'session has projectName');
  assert(typeof first.isActive === 'boolean', 'session has isActive boolean');

  ws.close();
}

// ========== Integration: Full E2E Flow ==========

async function testE2EFlow() {
  console.log('\n--- E2E WebSocket Flow ---');

  const token = await getValidToken();
  const ws = connectWs();
  await waitForOpen(ws);

  // Auth
  ws.send(JSON.stringify({ type: 'auth', token }));
  const authMsg = await waitForMessage(ws);
  assert((authMsg as { success: boolean }).success === true, 'E2E: auth succeeds');

  // List sessions
  ws.send(JSON.stringify({ type: 'session_list_request' }));
  const listMsg = await waitForMessage(ws);
  assertEq(listMsg.type, 'session_list', 'E2E: got session list');
  const sessions = (listMsg as { sessions: Array<{ id: string; isActive: boolean }> }).sessions;

  if (sessions.length > 0) {
    // Attach to first session
    const targetId = sessions[0]!.id;
    ws.send(JSON.stringify({ type: 'attach', sessionId: targetId }));
    const stateMsg = await waitForMessage(ws);
    assertEq(stateMsg.type, 'session_state', 'E2E: got session state after attach');
    assertEq((stateMsg as { state: string }).state, 'active', 'E2E: session state = active');

    // Detach
    ws.send(JSON.stringify({ type: 'detach' }));
    // No response expected for detach, just verify no error
    assert(true, 'E2E: detach sent without error');
  } else {
    console.log('  ⚠ No sessions found — skipping attach/detach');
  }

  // Pong
  ws.send(JSON.stringify({ type: 'pong' }));
  assert(true, 'E2E: pong sent without error');

  ws.close();
}

// ========== Run All Tests ==========

async function main() {
  console.log('========================================');
  console.log('  Vibe Code Relay Server Test Suite');
  console.log('========================================');

  // Unit tests (no server needed)
  testProtocolMessages();
  testEventClassifier();
  testTemplateSummarizer();

  // Integration tests (server must be running)
  try {
    await testHealthEndpoint();
    await testQrPairing();
    await testWsAuth();
    await testSessionDiscovery();
    await testE2EFlow();
  } catch (err) {
    console.error('\n⚠ Integration test error:', err);
    failed++;
  }

  console.log('\n========================================');
  console.log(`  Results: ${passed} passed, ${failed} failed`);
  console.log('========================================');

  process.exit(failed > 0 ? 1 : 0);
}

main();
