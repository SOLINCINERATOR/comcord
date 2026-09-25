const cfg = window.COMCORD_CONFIG;
const sb = supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
let me=null, currentServer=null, currentChannel=null, currentConversation=null, realtime=null;

const $ = id => document.getElementById(id);
function setStatus(t){$('authStatus').textContent=t||''}
function usernameEmail(u){return `${u.toLowerCase().replace(/[^a-z0-9._-]/g,'') || 'user'}@users.comcord.local`}

$('showRegister').onclick=()=>{$('loginBox').hidden=true;$('registerBox').hidden=false;setStatus('')}
$('showLogin').onclick=()=>{$('registerBox').hidden=true;$('loginBox').hidden=false;setStatus('')}

$('registerBtn').onclick=async()=>{
  const username=$('regUser').value.trim(), display=$('regDisplay').value.trim()||username;
  const realEmail=$('regEmail').value.trim(), password=$('regPassword').value;
  if(!username||!password) return setStatus('Username and password are required.');
  const email=realEmail||usernameEmail(username);
  setStatus('Creating account...');
  const {data,error}=await sb.auth.signUp({email,password,options:{data:{username,display_name:display}}});
  if(error) return setStatus(error.message);
  if(data.user) setStatus(realEmail?'Account created. Check your email if confirmation is enabled.':'Account created. You can log in now.');
}

$('loginBtn').onclick=async()=>{
  const u=$('loginUser').value.trim(), p=$('loginPassword').value;
  if(!u||!p) return setStatus('Enter username and password.');
  setStatus('Logging in...');
  const {data,error}=await sb.auth.signInWithPassword({email:usernameEmail(u),password:p});
  if(error) return setStatus(error.message);
  await boot(data.user);
}

$('logout').onclick=()=>sb.auth.signOut();

async function boot(user){
  me=user;
  $('auth').hidden=true;$('app').hidden=false;
  await loadProfile(); await loadServers(); await loadFriends();
}

async function loadProfile(){
  const {data}=await sb.from('profiles').select('*').eq('id',me.id).single();
  if(!data)return;
  $('myName').textContent=data.display_name||data.username;
  $('myStatus').textContent=data.status;
  $('profileDisplay').value=data.display_name||'';
  $('profileAvatar').value=data.avatar_url||'';
  $('profileBanner').value=data.banner_url||'';
  $('profileStatus').value=data.status||'online';
  $('myAvatar').innerHTML=data.avatar_url?`<img src="${escapeHtml(data.avatar_url)}">`:(data.display_name||'C')[0].toUpperCase();
}

$('saveProfile').onclick=async()=>{
  const {error}=await sb.from('profiles').update({
    display_name:$('profileDisplay').value.trim()||'User',
    avatar_url:$('profileAvatar').value.trim()||null,
    banner_url:$('profileBanner').value.trim()||null,
    status:$('profileStatus').value,
    updated_at:new Date().toISOString()
  }).eq('id',me.id);
  if(error) alert(error.message); else await loadProfile();
}

$('changePassword').onclick=async()=>{
  const p=prompt('New password:'); if(!p)return;
  const {error}=await sb.auth.updateUser({password:p});
  alert(error?error.message:'Password changed.');
}

$('createServer').onclick=()=>$('serverDialog').showModal();
$('addFriend').onclick=()=>$('friendDialog').showModal();

$('serverForm').onsubmit=async(e)=>{
  e.preventDefault();
  const name=$('serverName').value.trim(), max=Number($('serverMax').value), desc=$('serverDesc').value.trim();
  const {data,error}=await sb.from('servers').insert({name,description:desc,owner_id:me.id,max_members:max}).select().single();
  if(error)return alert(error.message);
  await sb.from('server_members').insert({server_id:data.id,user_id:me.id});
  const ch=await sb.from('channels').insert({server_id:data.id,name:'general',type:'text'}).select().single();
  $('serverDialog').close(); await loadServers();
  if(ch.data) selectChannel(ch.data);
}

async function loadServers(){
  const {data,error}=await sb.from('server_members').select('server_id, servers(id,name,icon_url,max_members)').eq('user_id',me.id);
  if(error)return console.error(error);
  const list=$('serverList');list.innerHTML='';
  (data||[]).forEach(x=>{
    const b=document.createElement('button');b.className='server-icon';b.title=`${x.servers.name} • max ${x.servers.max_members}`;
    b.textContent=(x.servers.name||'C')[0].toUpperCase();b.onclick=()=>selectServer(x.servers);list.appendChild(b);
  });
}

async function selectServer(server){
  currentServer=server;
  const {data}=await sb.from('channels').select('*').eq('server_id',server.id).order('position');
  $('channelList').innerHTML='';
  (data||[]).forEach(ch=>{
    const d=document.createElement('div');d.className='channel';d.textContent=(ch.type==='voice'?'🔊 ':'# ')+ch.name;
    d.onclick=()=>selectChannel(ch);$('channelList').appendChild(d);
  });
  $('chatHeader').innerHTML=`<strong>${escapeHtml(server.name)}</strong><span class="muted"> · max ${server.max_members}</span>`;
}

async function selectChannel(ch){
  currentChannel=ch;currentConversation=null;
  $('chatHeader').innerHTML=`<strong># ${escapeHtml(ch.name)}</strong>`;
  await loadChannelMessages();
  subscribeChannel();
}

async function loadChannelMessages(){
  $('messages').innerHTML='';
  const {data,error}=await sb.from('channel_messages').select('id,content,sender_id,created_at,profiles(username,display_name)').eq('channel_id',currentChannel.id).order('created_at');
  if(error)return;
  (data||[]).forEach(renderMessage);
  $('messages').scrollTop=$('messages').scrollHeight;
}

function renderMessage(m){
  const d=document.createElement('div');d.className='message';
  d.innerHTML=`<span class="name">${escapeHtml(m.profiles?.display_name||m.profiles?.username||'User')}</span><span class="time">${new Date(m.created_at).toLocaleString()}</span><div>${escapeHtml(m.content||'')}</div>`;
  $('messages').appendChild(d);
}

function subscribeChannel(){
  if(realtime)sb.removeChannel(realtime);
  realtime=sb.channel('channel-'+currentChannel.id).on('postgres_changes',{event:'INSERT',schema:'public',table:'channel_messages',filter:`channel_id=eq.${currentChannel.id}`},payload=>{
    renderMessage(payload.new);$('messages').scrollTop=$('messages').scrollHeight;
  }).subscribe();
}

$('messageForm').onsubmit=async e=>{
  e.preventDefault();const text=$('messageInput').value.trim();
  if(!text||!currentChannel)return;
  $('messageInput').value='';
  const {error}=await sb.from('channel_messages').insert({channel_id:currentChannel.id,sender_id:me.id,content:text});
  if(error)alert(error.message);
}

async function loadFriends(){
  const {data:friends}=await sb.from('friendships').select('*').or(`user_a.eq.${me.id},user_b.eq.${me.id}`);
  const ids=(friends||[]).map(f=>f.user_a===me.id?f.user_b:f.user_a);
  $('friendList').innerHTML='';
  if(!ids.length){$('friendList').innerHTML='<div class="empty">No friends yet.</div>';return}
  const {data}=await sb.from('profiles').select('id,username,display_name,status,avatar_url').in('id',ids);
  (data||[]).forEach(f=>{
    const d=document.createElement('div');d.className='friend';d.textContent=`${f.display_name||f.username} · ${f.status}`;
    d.onclick=()=>openDM(f);$('friendList').appendChild(d);
  });
}

$('friendForm').onsubmit=async e=>{
  e.preventDefault();const username=$('friendUsername').value.trim();
  const {data:user}=await sb.from('profiles').select('id,username').eq('username',username).single();
  if(!user)return alert('User not found.');
  if(user.id===me.id)return alert('You cannot add yourself.');
  const {error}=await sb.from('friend_requests').insert({sender_id:me.id,receiver_id:user.id});
  if(error)alert(error.message);else{$('friendDialog').close();alert('Friend request sent.')}
}

async function openDM(friend){
  let {data}=await sb.from('dm_conversations').select('*').or(`and(user_a.eq.${me.id},user_b.eq.${friend.id}),and(user_a.eq.${friend.id},user_b.eq.${me.id})`).limit(1).maybeSingle();
  if(!data){
    const r=await sb.from('dm_conversations').insert({user_a:me.id,user_b:friend.id}).select().single();
    if(r.error)return alert(r.error.message); data=r.data;
  }
  currentConversation=data;currentChannel=null;
  $('chatHeader').innerHTML=`<strong>DM: ${escapeHtml(friend.display_name||friend.username)}</strong>`;
  $('messages').innerHTML='';
  const {data:msgs}=await sb.from('dm_messages').select('*,profiles(username,display_name)').eq('conversation_id',data.id).order('created_at');
  (msgs||[]).forEach(renderMessage);
  if(realtime)sb.removeChannel(realtime);
  realtime=sb.channel('dm-'+data.id).on('postgres_changes',{event:'INSERT',schema:'public',table:'dm_messages',filter:`conversation_id=eq.${data.id}`},payload=>renderMessage(payload.new)).subscribe();
}

function escapeHtml(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]))}

sb.auth.getSession().then(async({data})=>{if(data.session)await boot(data.session.user)});
