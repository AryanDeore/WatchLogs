#!/usr/bin/env node

/**
 * Simulates a day boundary crossing in real-time to verify the fix works.
 * 
 * How it works:
 * 1. Sets target hour to the NEXT hour (e.g., if it's 10:45, sets to 11:00)
 * 2. Injects test activity that crosses that boundary
 * 3. Monitors the database to see if the day slides or freezes
 * 4. Reports results in real-time
 * 
 * This tests the ACTUAL fix code, not a mock.
 */

import { DatabaseSync } from 'node:sqlite';
import { homedir } from 'node:os';
import { join } from 'node:path';

const DB_PATH = process.env.WATCHLOGS_DB || join(homedir(), 'Library/Application Support/WatchLogs/watchlogs.sqlite');

function formatTime(ms) {
  const date = new Date(ms);
  return date.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

function formatDate(ms) {
  const date = new Date(ms);
  return date.toLocaleString('en-US', { 
    month: '2-digit', 
    day: '2-digit', 
    hour: '2-digit', 
    minute: '2-digit', 
    second: '2-digit',
    hour12: false 
  });
}

async function simulate() {
  console.log('=== Day Boundary Crossing Simulation ===\n');
  
  const db = new DatabaseSync(DB_PATH);
  const now = Date.now();
  const currentHour = new Date(now).getHours();
  const currentMinute = new Date(now).getMinutes();
  
  // Calculate next hour
  const nextHour = (currentHour + 1) % 24;
  const minutesUntilNextHour = 60 - currentMinute;
  
  console.log(`Current time: ${formatTime(now)}`);
  console.log(`Next hour: ${nextHour}:00 (in ${minutesUntilNextHour} minutes)\n`);
  
  // Step 1: Set target hour to next hour
  console.log('Step 1: Setting target hour...');
  const oldTargetHour = db.prepare('SELECT target_hour FROM day_settings WHERE id = 1').get()?.target_hour || 4;
  console.log(`  Current target hour: ${oldTargetHour}:00`);
  console.log(`  Setting to: ${nextHour}:00`);
  
  db.prepare('INSERT INTO day_settings (id, target_hour) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET target_hour = excluded.target_hour')
    .run(nextHour);
  
  console.log('  ✅ Target hour updated\n');
  
  // Step 2: Check current open day
  console.log('Step 2: Checking current open day...');
  const openDay = db.prepare('SELECT day_start_ms FROM open_day WHERE id = 1').get();
  if (openDay) {
    console.log(`  Current day started: ${formatDate(openDay.day_start_ms)}`);
  } else {
    console.log('  No open day yet');
  }
  console.log();
  
  // Step 3: Create test activity that will cross the boundary
  console.log('Step 3: Creating test activity...');
  console.log('  To properly test, you need to:');
  console.log('  1. Open a video in your browser NOW');
  console.log('  2. Keep it playing until AFTER the next hour');
  console.log(`  3. Stop it after ${nextHour}:01 (just 1 minute past)`);
  console.log('  4. Run this script again with --check to see results\n');
  
  console.log('Alternative: Use the --inject flag to create fake test data');
  console.log('  (This is less reliable but faster)\n');
  
  // Step 4: Set up monitoring
  console.log('Step 4: Monitoring instructions...');
  console.log(`  Watch at: ${nextHour}:00 - ${nextHour}:01`);
  console.log('  Expected behavior WITH fix:');
  console.log(`    - Day stays open past ${nextHour}:00`);
  console.log(`    - Day slides to ${nextHour + 1}:30 (90 min after boundary)`);
  console.log('  Bug behavior WITHOUT fix:');
  console.log(`    - Day freezes at exactly ${nextHour}:00`);
  console.log(`    - Activity after ${nextHour}:00 goes to new day\n`);
  
  console.log('Run `node tools/simulate-boundary-crossing.js --check` after the hour to see results');
  
  db.close();
}

async function checkResults() {
  console.log('=== Checking Simulation Results ===\n');
  
  const db = new DatabaseSync(DB_PATH);
  const now = Date.now();
  const currentHour = new Date(now).getHours();
  const targetHour = db.prepare('SELECT target_hour FROM day_settings WHERE id = 1').get()?.target_hour || 4;
  
  console.log(`Current time: ${formatTime(now)}`);
  console.log(`Target hour: ${targetHour}:00\n`);
  
  // Check if we're past the target hour
  const minutesSinceTarget = (currentHour * 60 + new Date(now).getMinutes()) - (targetHour * 60);
  
  if (minutesSinceTarget < 0) {
    console.log(`⏰ Target hour hasn't arrived yet. Current: ${currentHour}:00, Target: ${targetHour}:00`);
    console.log(`   Wait ${Math.abs(minutesSinceTarget)} more minutes\n`);
    db.close();
    return;
  }
  
  if (minutesSinceTarget > 120) {
    console.log(`⚠️  It's been ${minutesSinceTarget} minutes since target hour`);
    console.log('   The test period may have passed. Check rolled_day table.\n');
  }
  
  // Check current state
  console.log('Checking database state...\n');
  
  // Is there an open day?
  const openDay = db.prepare('SELECT day_start_ms FROM open_day WHERE id = 1').get();
  if (!openDay) {
    console.log('❌ No open day found - this is unusual\n');
    db.close();
    return;
  }
  
  console.log(`Open day started: ${formatDate(openDay.day_start_ms)}`);
  
  // Get target hour boundary time today
  const targetBoundaryMs = new Date(now).setHours(targetHour, 0, 0, 0);
  
  // Find activity around the boundary
  const crossingActivity = db.prepare(`
    SELECT 
      wall_start_ms,
      wall_end_ms,
      view_id,
      kind
    FROM segments
    WHERE kind = 'watched'
      AND wall_start_ms < ?
      AND wall_end_ms > ?
      AND wall_start_ms > ? - 3600000
    ORDER BY wall_start_ms
    LIMIT 5
  `).all(targetBoundaryMs, targetBoundaryMs, targetBoundaryMs);
  
  if (crossingActivity.length === 0) {
    console.log(`\n⚠️  No activity found crossing ${targetHour}:00`);
    console.log('   Did you watch something across the boundary?');
    console.log('   If not, create test activity and try again.\n');
    db.close();
    return;
  }
  
  console.log(`\n✅ Found ${crossingActivity.length} segment(s) crossing the boundary:`);
  crossingActivity.forEach(seg => {
    console.log(`   ${formatTime(seg.wall_start_ms)} → ${formatTime(seg.wall_end_ms)} (${seg.kind})`);
  });
  
  // Check if the day is still open or has been frozen
  const frozenDay = db.prepare(`
    SELECT 
      logical_date,
      day_start_ms,
      day_end_ms
    FROM rolled_day
    WHERE day_start_ms = ?
  `).get(openDay.day_start_ms);
  
  if (frozenDay) {
    console.log(`\n📊 Day has been FROZEN:`);
    console.log(`   Date: ${frozenDay.logical_date}`);
    console.log(`   Start: ${formatDate(frozenDay.day_start_ms)}`);
    console.log(`   End: ${formatDate(frozenDay.day_end_ms)}`);
    
    const frozenAtTarget = Math.abs(frozenDay.day_end_ms - targetBoundaryMs) < 60000; // within 1 minute
    
    if (frozenAtTarget) {
      console.log(`\n❌ BUG: Day froze at exactly ${targetHour}:00!`);
      console.log('   This is the same bug from Sept 6.');
      console.log('   The fix did NOT work or is not applied.\n');
    } else {
      const slidMinutes = Math.round((frozenDay.day_end_ms - targetBoundaryMs) / 60000);
      console.log(`\n✅ SUCCESS: Day slid by ${slidMinutes} minutes!`);
      console.log(`   Expected: ~90 minutes (if fix is working)`);
      console.log(`   Actual: ${slidMinutes} minutes`);
      
      if (slidMinutes >= 85 && slidMinutes <= 95) {
        console.log('   ✅ This matches the expected slide behavior!\n');
      } else if (slidMinutes > 0) {
        console.log('   ⚠️  Day slid but not by 90 minutes. Check activity duration.\n');
      }
    }
  } else {
    console.log(`\n⏳ Day is still OPEN:`);
    console.log(`   This is expected if we're within 90 minutes of the last activity.`);
    console.log(`   The day should freeze at: [last activity time] + 90 minutes`);
    
    const lastActivity = db.prepare(`
      SELECT MAX(wall_end_ms) as last_end
      FROM segments
      WHERE kind = 'watched'
        AND wall_start_ms >= ?
    `).get(openDay.day_start_ms);
    
    if (lastActivity && lastActivity.last_end) {
      const expectedFreezeTime = lastActivity.last_end + (90 * 60 * 1000);
      const minutesUntilFreeze = Math.round((expectedFreezeTime - now) / 60000);
      
      console.log(`   Last activity: ${formatTime(lastActivity.last_end)}`);
      console.log(`   Should freeze at: ${formatTime(expectedFreezeTime)}`);
      
      if (minutesUntilFreeze > 0) {
        console.log(`   ⏰ Check again in ${minutesUntilFreeze} minutes\n`);
      } else {
        console.log(`   ⚠️  Should have frozen already. May need a flush to trigger.\n`);
      }
    }
  }
  
  db.close();
}

async function injectTestData() {
  console.log('=== Injecting Test Data ===\n');
  console.log('⚠️  WARNING: This modifies your database!');
  console.log('Creating fake test segments...\n');
  
  const db = new DatabaseSync(DB_PATH);
  const now = Date.now();
  const currentHour = new Date(now).getHours();
  const nextHour = (currentHour + 1) % 24;
  const targetHour = nextHour;
  
  // Set target hour
  db.prepare('INSERT INTO day_settings (id, target_hour) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET target_hour = excluded.target_hour')
    .run(targetHour);
  
  console.log(`✅ Set target hour to ${targetHour}:00`);
  
  // Create boundary time
  const boundaryMs = new Date(now).setHours(targetHour, 0, 0, 0);
  if (boundaryMs < now) {
    // Target hour already passed today, use tomorrow
    boundaryMs += 24 * 60 * 60 * 1000;
  }
  
  // Create test view and segments
  const testViewId = `test-boundary-${Date.now()}`;
  const tabId = 99999;
  
  // Segment before boundary
  const beforeStart = boundaryMs - 5 * 60 * 1000; // 5 min before
  const beforeEnd = boundaryMs - 30 * 1000; // 30 sec before
  
  // Crossing segment
  const crossStart = boundaryMs - 60 * 1000; // 1 min before
  const crossEnd = boundaryMs + 5 * 60 * 1000; // 5 min after
  
  // Segment after
  const afterStart = boundaryMs + 20 * 60 * 1000; // 20 min after
  const afterEnd = boundaryMs + 25 * 60 * 1000; // 25 min after
  
  console.log(`\nCreating test segments:`);
  console.log(`  Before: ${formatTime(beforeStart)} → ${formatTime(beforeEnd)}`);
  console.log(`  Crossing: ${formatTime(crossStart)} → ${formatTime(crossEnd)} ← CROSSES BOUNDARY`);
  console.log(`  After: ${formatTime(afterStart)} → ${formatTime(afterEnd)}`);
  
  // Insert view
  db.prepare(`
    INSERT INTO views (
      view_id, service, content_format, video_id, url, 
      adapter_id, tab_id, started_at_ms, open
    ) VALUES (?, 'test', 'standard', 'test-video', 'https://test.com/video', 
              'test', ?, ?, 0)
  `).run(testViewId, tabId, beforeStart);
  
  // Insert segments
  db.prepare(`
    INSERT INTO segments (view_id, kind, wall_start_ms, wall_end_ms, pos_start, pos_end, provisional)
    VALUES (?, 'watched', ?, ?, 0, 10, 0)
  `).run(testViewId, beforeStart, beforeEnd);
  
  db.prepare(`
    INSERT INTO segments (view_id, kind, wall_start_ms, wall_end_ms, pos_start, pos_end, provisional)
    VALUES (?, 'watched', ?, ?, 10, 20, 0)
  `).run(testViewId, crossStart, crossEnd);
  
  db.prepare(`
    INSERT INTO segments (view_id, kind, wall_start_ms, wall_end_ms, pos_start, pos_end, provisional)
    VALUES (?, 'watched', ?, ?, 20, 30, 0)
  `).run(testViewId, afterStart, afterEnd);
  
  console.log('\n✅ Test data injected');
  console.log('\n⏰ Wait until after the boundary time, then run:');
  console.log('   node tools/simulate-boundary-crossing.js --check\n');
  
  db.close();
}

// Parse args
const args = process.argv.slice(2);
const command = args[0];

if (command === '--check') {
  checkResults().catch(console.error);
} else if (command === '--inject') {
  injectTestData().catch(console.error);
} else if (command === '--help' || command === '-h') {
  console.log(`
Usage: node tools/simulate-boundary-crossing.js [command]

Commands:
  (none)      Set up simulation and show instructions
  --check     Check results after boundary crossing
  --inject    Inject fake test data (modifies database!)
  --help      Show this help

Example workflow:
  1. node tools/simulate-boundary-crossing.js          # Set up
  2. Watch a video across the next hour boundary
  3. node tools/simulate-boundary-crossing.js --check  # See results

Or use --inject for quick (but less reliable) testing.
`);
} else {
  simulate().catch(console.error);
}
