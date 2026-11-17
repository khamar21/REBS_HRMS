const express = require('express');
const app = express();
app.use(express.json());

const numberFromEnv = (name, fallback) => {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
};

// Office location (override with environment variables).
const OFFICE = {
  lat: numberFromEnv('OFFICE_LAT', 11.02981),
  lng: numberFromEnv('OFFICE_LNG', 76.26145),
  radiusMeters: numberFromEnv('OFFICE_RADIUS_METERS', 200),
};
const employee = {
  id: 'EMP001', name: 'Demo Employee', department: 'Engineering',
  timezone: 'Asia/Kolkata', office: OFFICE,
};

const events = new Map();   // eventId -> stored response (idempotency)
const attendance = {};      // 'YYYY-MM-DD' -> { date, checkIn, checkOut }
const initialLeaveBalance = { casual: 6, sick: 4 };
let leaveBalance = { ...initialLeaveBalance };
const initialLeaveRequests = [
  { id: 'L1', type: 'casual', startDate: '2026-12-01', endDate: '2026-12-02',
    reason: 'Family function', status: 'approved' },
];
const leaveRequests = [...initialLeaveRequests];

const resetState = () => {
  events.clear();
  Object.keys(attendance).forEach((date) => delete attendance[date]);
  leaveBalance = { ...initialLeaveBalance };
  leaveRequests.splice(0, leaveRequests.length, ...initialLeaveRequests);
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const scenario = (req) => req.header('x-scenario') || 'success';

// Health check (also used to wake a hosted server).
app.get('/', (_, res) => res.json({ status: 'ok' }));

// Scenario handling: slow / error500
app.use(async (req, res, next) => {
  const s = scenario(req);
  if (s === 'slow') await sleep(5000);
  if (s === 'error500') return res.status(500).json({ code: 'SERVER_ERROR' });
  next();
});

app.get('/employee/me', (_, res) => res.json(employee));

// Reset in-memory data between repeatable review scenarios.
app.post('/__reset', (_, res) => {
  resetState();
  res.json({ status: 'reset' });
});

app.get('/attendance', (req, res) => {
  const month = req.query.month;
  res.json(Object.values(attendance).filter((a) => a.date.startsWith(month)));
});

app.post('/attendance/events', async (req, res) => {
  const { eventId, type, timestamp, date } = req.body;
  if (!eventId || !type || !timestamp || !date)
    return res.status(400).json({ code: 'BAD_REQUEST' });

  // Idempotency: the same eventId always returns the original result.
  if (events.has(eventId)) return res.status(200).json(events.get(eventId));

  const s = scenario(req);
  let rec = attendance[date];

  if (type === 'check_in') {
    if (rec || s === 'duplicate')
      return res.status(409).json({ code: 'ATTENDANCE_EXISTS',
        message: 'Attendance already exists for this date' });
    rec = attendance[date] = { date, checkIn: timestamp, checkOut: null };
  } else if (type === 'check_out') {
    if (!rec) return res.status(422).json({ code: 'NO_CHECK_IN',
      message: 'Check-out requires a check-in' });
    if (rec.checkOut) return res.status(409).json({ code: 'ALREADY_CHECKED_OUT',
      message: 'Already checked out' });
    rec.checkOut = timestamp;
  } else return res.status(400).json({ code: 'BAD_TYPE' });

  const result = { eventId, status: 'synced', record: rec };
  events.set(eventId, result);

  // Timeout scenario: the server SAVED the event but never replies.
  // The client times out; its retry with the same eventId gets a 200.
  if (s === 'timeout') return;
  res.status(201).json(result);
});

app.get('/leave/balance', (_, res) => res.json(leaveBalance));
app.get('/leave/requests', (_, res) => res.json(leaveRequests));

app.post('/leave/requests', (req, res) => {
  const { type, startDate, endDate, reason } = req.body;
  if (scenario(req) === 'leave_reject')
    return res.status(422).json({ code: 'LEAVE_REJECTED',
      message: 'Leave rejected by server policy' });
  const days = (new Date(endDate) - new Date(startDate)) / 864e5 + 1;
  if (days > leaveBalance[type])
    return res.status(422).json({ code: 'INSUFFICIENT_BALANCE',
      message: 'Not enough leave balance' });
  const overlap = leaveRequests.some((r) =>
    r.status !== 'rejected' && startDate <= r.endDate && endDate >= r.startDate);
  if (overlap) return res.status(422).json({ code: 'OVERLAP',
    message: 'Dates overlap an existing request' });
  const r = { id: 'L' + (leaveRequests.length + 1), type, startDate, endDate,
    reason, status: 'pending' };
  leaveRequests.push(r);
  res.status(201).json(r);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => console.log('Mock API on :' + PORT));