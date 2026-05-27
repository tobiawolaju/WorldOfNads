# World Of Nads Analytics

## Overview
This analytics system tracks traction, growth, engagement, and economic activity for grant and investor reporting. Events are stored in PostgreSQL (`analytics_events`) and summarized by the `/analytics/summary` and `/analytics/timeseries` endpoints. The dashboard at `/admin/analytics` provides a visual view of the most important metrics.

## Metrics Explained (and Why They Matter)

### User Metrics
- **DAU (Daily Active Users)**: Unique users with any activity in a day. Shows daily traction.
- **WAU (Weekly Active Users)**: Unique users active in the last 7 days. Shows short-term retention.
- **MAU (Monthly Active Users)**: Unique users active in the last 30 days. Shows longer-term retention.
- **Total Users**: Unique users ever seen. Indicates ecosystem size.
- **New Users per Day**: Registrations per day. Indicates acquisition rate.
- **Unique Users per Day**: Unique active users per day. Shows day-to-day usage.

### Growth Metrics
- **Daily User Growth Rate**: Change in daily unique users vs. the previous day. Indicates acceleration.
- **Weekly Growth Rate**: Change in weekly active users vs. the previous 7 days. Shows sustained growth.
- **Match Creation Growth Rate**: Change in match creation vs. the previous 7 days. Shows content velocity.

### Game Metrics
- **Matches Created per Day**: Count of match creation events per day. Shows content supply.
- **Matches Completed**: Total completed matches. Shows core gameplay throughput.
- **Matches Currently Active**: Matches started but not finished. Indicates live concurrency.
- **Average Players per Match**: Engagement density per match.
- **Match Completion Rate**: Completed / started matches. Shows match quality and engagement.
- **Matches per User**: Average matches joined per user. Indicates depth of play.

### Reward / Economy Metrics
- **Total Rewards Distributed**: Sum of reward payouts. Shows economic activity.
- **Rewards Distributed per Day**: Daily reward payout volume. Shows ongoing economy.
- **Average Reward per Match**: Rewards per match. Shows incentive efficiency.
- **Total Reward Volume**: Overall reward pool paid out.
- **Top Winning Players**: High-value winners. Useful for spotlighting power users.

### Sponsor Metrics
- **Total Sponsors**: Unique sponsors ever seen. Shows ecosystem support.
- **Matches Sponsored**: Count of sponsor-funded matches. Shows sponsor engagement.
- **Sponsor Funding Volume**: Sum of sponsor-funded prizes. Shows sponsor spend.
- **Average Sponsor Value**: Average sponsor contribution. Shows deal size.

### Engagement Metrics
- **Average Session Duration**: Mean session length in seconds. Shows stickiness.
- **Returning Users vs New Users**: Repeat engagement vs acquisition.
- **Games Played per User**: Matches completed per user. Shows engagement depth.
- **Retention (D1/D7/D30)**: Percent of users returning after 1, 7, 30 days. Key investor KPI.

### Grant Metrics (Required for Applications)
- **Daily Active Users**
- **Total Users**
- **Total Matches Played**
- **Total Rewards Distributed**
- **Number of Sponsors**
- **Average Matches per User**
- **User Growth Rate**
- **Match Growth Rate**
- **Day 7 Retention**

## Event Tracking
Events are logged via the `POST /analytics/events` endpoint or via backend calls. Each event row is stored in `analytics_events` with fields:

- `event_type`
- `user_id`
- `match_id`
- `sponsor_id`
- `value`
- `metadata` (JSON string)
- `timestamp`

### Event Types Implemented
- `user_registered`
- `user_joined`
- `session_started`
- `session_ended`
- `match_created`
- `match_joined`
- `match_started`
- `match_finished`
- `reward_paid`
- `sponsor_added`
- `sponsor_match_created`

### Frontend Tracking
The frontend emits events through `frontend/src/lib/analyticsClient.js`. Key call sites:
- `saveUserToFirebase` logs `user_registered` and `user_joined`.
- `App.tsx` logs session start/end.
- `Dashboard.tsx` logs `match_joined`.
- `SpounsorDashbaord.jsx` logs `match_created`, `sponsor_added`, and `sponsor_match_created`.

### Backend Tracking
The backend logs:
- `match_started` and `match_finished` when the match status worker updates Firebase.
- `reward_paid` when a payout is saved.

## Opening the Dashboard
1. Start the backend server.
2. Visit `/admin/analytics` on the frontend.
3. Enter the access code from `ADMIN_ACCESS_CODE`.

## Exporting Analytics Data
Use the dashboard export buttons or call directly:
- `GET /analytics/export?format=csv&start=YYYY-MM-DD&end=YYYY-MM-DD`
- `GET /analytics/export?format=json&start=YYYY-MM-DD&end=YYYY-MM-DD`

Exports include the raw events in the selected date range.

## Environment Variables
- `ANALYTICS_DB_URL`: PostgreSQL connection string.
- `ADMIN_ACCESS_CODE`: Access code for the analytics dashboard.
- `PORT`: Backend server port.
- `VITE_ANALYTICS_API_URL`: Frontend URL to reach the analytics API.

## Notes
- Retention is calculated based on `user_registered` cohorts and subsequent activity.
- Average session duration requires both `session_started` and `session_ended` events.
