# Comcord – Supabase Starter

Comcord is a Discord-inspired starter project with a black/gray UI.

Included:
- Supabase Auth login/register
- Username + password login
- Optional real email
- Profiles, avatar and banner URLs
- Friends + friend requests
- Direct messages
- Groups/servers
- Configurable maximum member count (5, 20, 25, 100, etc.)
- Invite links
- Text channels
- Realtime chat
- Basic server roles/permissions database foundation

IMPORTANT
1. Create a Supabase project.
2. Open SQL Editor.
3. Paste ALL of `supabase_schema.sql` and run it.
4. In Authentication > Providers > Email, disable email confirmation if you want username-only accounts to work without a real email.
5. Put your Supabase URL and ANON/PUBLISHABLE key in `config.js`.
6. Open `index.html` through a local web server. Do not expose a service_role/secret key in the browser.

Username-only accounts:
The starter maps a username to an internal email such as username@users.comcord.local.
If the user does not add a real email, password recovery by email cannot work. They can still change their password while logged in.

For production:
- Add Storage buckets for avatars, banners, images, files and audio.
- Add Edge Functions for moderation, secure invite handling and call signaling.
- Use a WebRTC SFU (for example LiveKit/mediasoup) for large voice rooms. Supabase alone is a database/realtime backend; it is not the voice media server.
