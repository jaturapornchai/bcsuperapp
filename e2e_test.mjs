// End-to-End (E2E) Automated Test Suite for BC Super App (15 Full Enterprise Flows)
// Tests: Rust Backend + MongoDB + MinIO + WebSocket + Enterprise Confidentiality + Instant Recall & File Purge + DeepSeek AI Brain + Task Claiming + In-Chat Approval + Employee Offboarding Handover

const BASE_URL = process.env.API_URL || 'http://127.0.0.1:8095';

function assert(condition, message) {
  if (!condition) {
    throw new Error(`❌ ASSERTION FAILED: ${message}`);
  }
}

async function req(method, path, token = null, body = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_) {}
  return { status: res.status, ok: res.ok, json, text };
}

async function runE2E() {
  console.log('🚀 เริ่มการทดสอบ E2E — BC Super App (15 ขั้นตอนครบวงจร)...\n');

  // 1. Health Check (MongoDB + MinIO)
  const health = await req('GET', '/api/health');
  assert(health.ok && health.json?.status === 'ok', `Health check failed: ${health.text}`);
  console.log('✅ [1/15] Health Check ผ่าน (MongoDB & MinIO เชื่อมต่อปกติ)');

  // 2. Gmail Login (Admin & Employee)
  const adminLogin = await req('POST', '/api/auth/google', null, {
    email: 'jead@bcapp.local',
    display_name: 'ลุงจืด (Super Admin)',
  });
  assert(adminLogin.ok && adminLogin.json?.token, `Admin login failed: ${adminLogin.text}`);
  const adminToken = adminLogin.json.token;
  const adminUser = adminLogin.json.user;

  const empLogin = await req('POST', '/api/auth/google', null, {
    email: 'somchai.sales@bcapp.local',
    display_name: 'สมชาย ฝ่ายขาย',
  });
  assert(empLogin.ok && empLogin.json?.token, `Employee login failed: ${empLogin.text}`);
  const empToken = empLogin.json.token;
  const empUser = empLogin.json.user;
  console.log(`✅ [2/15] เข้าสู่ระบบด้วย Gmail สำเร็จ (${adminUser.email} & ${empUser.email})`);

  // 3. Profile Update & Search Friends by BC ID / Gmail / QR
  const updateProf = await req('PUT', '/api/auth/profile', adminToken, {
    display_name: 'ลุงจืด (ผู้บริหาร)',
    bc_id: 'jead.bc',
    status_message: 'ระบบแชทองค์กร BC Super App',
    department: 'บริหาร',
    job_title: 'ประธานเจ้าหน้าที่บริหาร',
  });
  assert(updateProf.ok, `Profile update failed: ${updateProf.text}`);

  const searchRes = await req('GET', `/api/users/search?q=somchai`, adminToken);
  assert(searchRes.ok && Array.isArray(searchRes.json) && searchRes.json.length > 0, 'User search failed');

  const addFriend = await req('POST', '/api/friends/add', adminToken, {
    target_id: empUser.id,
  });
  assert(addFriend.ok && addFriend.json?.conversation_id, `Add friend failed: ${addFriend.text}`);
  const directConvId = addFriend.json.conversation_id;
  console.log(`✅ [3/15] ค้นหาเพื่อนด้วย BC ID / Gmail และเปิดห้องแชท 1-1 สำเร็จ (conv_id: ${directConvId})`);

  // 4. Create Enterprise Group Chat & Set Work Folder
  const groupRes = await req('POST', '/api/conversations/group', adminToken, {
    name: 'ห้องประชุมความลับผู้บริหาร E2E',
    folder: 'work',
    member_ids: [empUser.id],
  });
  assert(groupRes.ok && groupRes.json?.id, `Create group failed: ${groupRes.text}`);
  const groupConvId = groupRes.json.id;

  const metaRes = await req('PUT', `/api/conversations/${groupConvId}/meta`, adminToken, {
    folder: 'work',
    is_pinned: true,
    name: 'ห้องประชุมความลับผู้บริหาร E2E',
  });
  assert(metaRes.ok, `Update conversation meta failed: ${metaRes.text}`);
  console.log('✅ [4/15] สร้างกลุ่มองค์กร แยกโฟลเดอร์ "เรื่องงาน" และปักหมุดห้องแชทสำเร็จ');

  // 5. Send Normal Message & Verify "อ่านแล้ว" (Read Receipt)
  const msg1 = await req('POST', `/api/conversations/${directConvId}/messages`, adminToken, {
    type: 'text',
    content: 'สวัสดีสมชาย ส่งสรุปยอดขายเดือนนี้และเตรียมใบเสนอราคาลูกค้าใหม่ให้ด้วยครับ',
  });
  assert(msg1.ok && msg1.json?.id, `Send message failed: ${msg1.text}`);

  const readRes = await req('POST', `/api/conversations/${directConvId}/read`, empToken, {});
  assert(readRes.ok, `Mark read failed: ${readRes.text}`);

  const msgsAfterRead = await req('GET', `/api/conversations/${directConvId}/messages`, adminToken);
  assert(msgsAfterRead.ok && Array.isArray(msgsAfterRead.json), 'Fetch messages failed');
  const readMsg = msgsAfterRead.json.find((m) => m.id === msg1.json.id);
  assert(readMsg && readMsg.read_count >= 1, `Expected read_count >= 1 after read, got: ${JSON.stringify(readMsg)}`);
  console.log(`✅ [5/15] ส่งข้อความและตรวจสอบสถานะ "อ่านแล้ว" (read_count = ${readMsg.read_count}) สำเร็จ`);

  // 6. Pin Announcement Banner on Chat Header
  const pinRes = await req('PUT', `/api/conversations/${directConvId}/pin-message`, adminToken, {
    message_id: msg1.json.id,
  });
  assert(pinRes.ok, `Pin message failed: ${pinRes.text}`);
  console.log('✅ [6/15] ปักหมุดประกาศสำคัญไว้บนหัวห้องแชท (Pin Banner) สำเร็จ');

  // 7. Upload Permanent File to MinIO & Verify Vault (No Expiration)
  const sampleContent = Buffer.from('เอกสารงบการเงินประจำปี BC Enterprise - ห้ามหมดอายุ').toString('base64');
  const upload1 = await req('POST', '/api/upload', adminToken, {
    file_name: 'financial_report_2026.txt',
    mime_type: 'text/plain',
    data_base64: sampleContent,
  });
  assert(upload1.ok && upload1.json?.key, `Upload to MinIO failed: ${upload1.text}`);

  const fileDownload = await fetch(`${BASE_URL}/api/files/${upload1.json.key}`);
  assert(fileDownload.ok, 'Download permanent file from MinIO failed');

  const fileMsg = await req('POST', `/api/conversations/${directConvId}/messages`, adminToken, {
    type: 'file',
    content: 'financial_report_2026.txt',
    attachment: upload1.json,
  });
  assert(fileMsg.ok, `Send file message failed: ${fileMsg.text}`);

  const vaultRes = await req('GET', `/api/conversations/${directConvId}/vault`, adminToken);
  assert(vaultRes.ok && vaultRes.json?.files?.length >= 1, `Vault check failed: ${vaultRes.text}`);
  console.log(`✅ [7/15] อัปโหลดไฟล์เก็บถาวรใน MinIO (${upload1.json.key}) และตรวจคลังไฟล์ประจำห้องแชทสำเร็จ`);

  // 8. Confidential Message + Sent Wrong Message -> Instant Recall & MinIO File Purge!
  const secretFileBase64 = Buffer.from('ข้อมูลความลับสูงสุด ส่งผิดห้อง ต้องลบออกจาก MinIO ทันที').toString('base64');
  const secretUpload = await req('POST', '/api/upload', adminToken, {
    file_name: 'top_secret_wrong_room.pdf',
    mime_type: 'application/pdf',
    data_base64: secretFileBase64,
  });
  assert(secretUpload.ok && secretUpload.json?.key, 'Secret upload failed');
  const secretKey = secretUpload.json.key;

  const secretMsg = await req('POST', `/api/conversations/${directConvId}/messages`, adminToken, {
    type: 'file',
    content: 'ไฟล์ความลับส่งผิดห้อง',
    is_confidential: true,
    attachment: secretUpload.json,
  });
  assert(secretMsg.ok && secretMsg.json?.id, `Send confidential message failed: ${secretMsg.text}`);

  const unsendRes = await req('DELETE', `/api/messages/${secretMsg.json.id}/unsend?hard=true`, adminToken);
  assert(unsendRes.ok, `Unsend/Purge failed: ${unsendRes.text}`);

  const checkDeletedFile = await fetch(`${BASE_URL}/api/files/${secretKey}`);
  assert(checkDeletedFile.status === 404, `Expected 404 for purged MinIO file, got ${checkDeletedFile.status}`);
  console.log('✅ [8/15] ทดสอบโหมดความลับ + ส่งผิดลบได้ทันที (ลบข้อความไร้ร่องรอย & ทำลายไฟล์ออกจาก MinIO จริง 100%) สำเร็จ');

  // 9. Keep & Group Notes
  const noteRes = await req('POST', '/api/notes', adminToken, {
    conversation_id: directConvId,
    title: 'สรุปข้อตกลงลูกค้า VIP',
    content: 'อนุมัติส่วนลดพิเศษ 5% สำหรับออเดอร์ล็อตใหญ่',
    is_pinned: true,
  });
  assert(noteRes.ok && noteRes.json?.id, `Create note failed: ${noteRes.text}`);
  console.log('✅ [9/15] บันทึก BC Keep / สมุดโน้ตประจำห้องแชทสำเร็จ');

  // 10. Super App Mini-App WebView & Rich Flex Card into Chat
  const miniApps = await req('GET', '/api/mini-apps', adminToken);
  assert(miniApps.ok && Array.isArray(miniApps.json) && miniApps.json.length >= 4, 'Fetch mini-apps failed');

  const webviewHtml = await fetch(`${BASE_URL}/miniapp/leave?token=${adminToken}&conv_id=${directConvId}`);
  assert(webviewHtml.ok, 'Mini-App WebView HTML endpoint failed');

  const flexMsg = await req('POST', `/api/conversations/${directConvId}/messages`, empToken, {
    type: 'flex_card',
    content: 'ใบขออนุมัติลาพักร้อน (2 วัน)',
    flex_payload: {
      app_code: 'leave_approval',
      title: 'ใบขออนุมัติลาพักร้อน',
      subtitle: 'สมชาย ฝ่ายขาย • 10-11 พ.ย. 2026',
      status: 'รออนุมัติ',
      color_hex: '#06C755',
      fields: [
        { label: 'ผู้ขออนุมัติ', value: 'สมชาย ฝ่ายขาย' },
        { label: 'จำนวนวัน', value: '2 วัน' },
      ],
    },
  });
  assert(flexMsg.ok && flexMsg.json?.type === 'flex_card', 'Send Flex Card message failed');
  console.log('✅ [10/15] เปิดระบบเสริม Mini-App WebView และส่งการ์ด Flex Card เข้าห้องแชทสำเร็จ');

  // 11. DeepSeek AI Brain (Summarize Chat, Polish Text, & @ai Group Co-Pilot)
  const aiSettings = await req('GET', '/api/admin/ai-settings', adminToken);
  assert(aiSettings.ok && aiSettings.json?.has_api_key === true, `AI settings check failed: ${aiSettings.text}`);
  assert(
    aiSettings.json?.masked_key?.includes('****') && !aiSettings.json?.api_key,
    'API Key must be masked and never exposed in response!'
  );

  const aiSum = await req('POST', '/api/ai/summarize', adminToken, {
    conversation_id: directConvId,
  });
  assert(aiSum.ok && aiSum.json?.summary, `AI summarize failed: ${aiSum.text}`);

  const aiAssist = await req('POST', '/api/ai/assist', adminToken, {
    conversation_id: directConvId,
    prompt: 'พรุ่งนี้ส่งใบเสนอราคาให้ลูกค้านะ',
    mode: 'formal',
  });
  assert(aiAssist.ok && aiAssist.json?.result, `AI assist failed: ${aiAssist.text}`);

  const aiMention = await req('POST', `/api/conversations/${groupConvId}/messages`, adminToken, {
    type: 'text',
    content: '@ai ช่วยสรุปหัวข้อการประชุมผู้บริหารวันนี้สั้นๆ 1 ประโยคครับ',
  });
  assert(aiMention.ok, `Send @ai mention failed: ${aiMention.text}`);
  console.log(`✅ [11/15] ทดสอบสมองกล DeepSeek AI (ซ่อนคีย์ปลอดภัย: ${aiSettings.json.masked_key}, สรุปแชท, เกลาคำพูด, และเรียก @ai ในกลุ่ม) สำเร็จ`);

  // 12. Urgent DING Message & Task Claiming ("กดรับงาน" -> "เสร็จสิ้น")
  const urgentMsg = await req('POST', `/api/conversations/${directConvId}/messages`, adminToken, {
    type: 'text',
    content: 'ด่วนมาก! ช่วยส่งใบเสนอราคาลูกค้า VIP ภายใน 15:00 น. วันนี้',
    priority: 'urgent',
    task_status: 'open',
  });
  assert(urgentMsg.ok && urgentMsg.json?.priority === 'urgent', `Send urgent message failed: ${urgentMsg.text}`);

  const claimRes = await req('POST', `/api/messages/${urgentMsg.json.id}/task-action`, empToken, {
    action: 'accept',
  });
  assert(
    claimRes.ok && claimRes.json?.task_status === 'accepted' && claimRes.json?.accepted_by,
    `Claim task failed: ${claimRes.text}`
  );

  const doneRes = await req('POST', `/api/messages/${urgentMsg.json.id}/task-action`, empToken, {
    action: 'done',
  });
  assert(doneRes.ok && doneRes.json?.task_status === 'done', `Complete task failed: ${doneRes.text}`);
  console.log(`✅ [12/15] ทดสอบโหมดด่วนพิเศษ (DING) และปุ่ม "กดรับงาน" -> "งานเสร็จแล้ว" โดย ${claimRes.json.accepted_by} สำเร็จ`);

  // 13. In-Chat Live Flex Card Approval & E-Signature
  const approveCardRes = await req('POST', `/api/messages/${flexMsg.json.id}/approve-card`, adminToken, {
    status: 'อนุมัติแล้ว',
    comment: 'อนุมัติเรียบร้อยครับ',
  });
  assert(
    approveCardRes.ok && approveCardRes.json?.flex_payload?.status === 'อนุมัติแล้ว',
    `Approve flex card failed: ${approveCardRes.text}`
  );
  console.log(`✅ [13/15] ทดสอบการกดอนุมัติการ์ดใบลา/เอกสารในห้องแชทพร้อมประทับชื่อผู้อนุมัติ (${approveCardRes.json.flex_payload.approved_by}) สำเร็จ`);

  // 14. Employee Offboarding 1-Click Chat Handover + AI Briefing
  const nidaLogin = await req('POST', '/api/auth/google', null, {
    email: 'nida.acc@bcapp.local',
    display_name: 'นิดา บัญชีการเงิน',
  });
  const handoverRes = await req('POST', '/api/admin/handover', adminToken, {
    from_user_id: empUser.id,
    to_user_id: nidaLogin.json.user.id,
  });
  assert(
    handoverRes.ok && handoverRes.json?.transferred_conversations >= 1,
    `Chat handover failed: ${handoverRes.text}`
  );
  console.log(`✅ [14/15] ทดสอบโอนย้ายห้องแชทเมื่อพนักงานลาออก/เปลี่ยนคนดูแล (${handoverRes.json.transferred_conversations} ห้อง พร้อม AI Briefing) สำเร็จ`);

  // 15. Admin Backoffice: Overview Stats, Dynamic Mini-App Creation, & Broadcast
  const overview = await req('GET', '/api/admin/overview', adminToken);
  assert(overview.ok && overview.json?.total_users >= 3, `Admin overview failed: ${overview.text}`);

  const newMiniApp = await req('POST', '/api/admin/mini-apps', adminToken, {
    app_code: 'stock_checker',
    title: 'เช็คสต๊อกคลังสินค้า (Realtime)',
    subtitle: 'เพิ่มจากหลังบ้านทันทีไม่ต้องอัปเดตแอป',
    category: 'work',
    icon_name: 'inventory_2',
    color_hex: '#0D9488',
    entry_url: `${BASE_URL}/miniapp/stock_checker`,
    is_active: true,
    sort_order: 5,
  });
  assert(newMiniApp.ok && newMiniApp.json?.id, `Create dynamic mini-app failed: ${newMiniApp.text}`);

  const broadcast = await req('POST', '/api/admin/broadcast', adminToken, {
    title: 'ประกาศจากผู้บริหาร',
    content: 'เปิดใช้งานระบบกดรับงานในแชท อนุมัติการ์ดด่วน และโอนงานอัตโนมัติด้วย DeepSeek AI',
  });
  assert(broadcast.ok, `Admin broadcast failed: ${broadcast.text}`);
  console.log('✅ [15/15] ระบบหลังบ้าน Admin Backoffice (สถิติระบบ, เพิ่ม Mini-App WebView สดไม่ต้องอัปเดตแอป, และประกาศ Broadcast) สำเร็จ\n');

  console.log('🎉 ผลการทดสอบ E2E ทั้งหมด 15 ขั้นตอน: ผ่านครบ 100%!');
}

runE2E().catch((err) => {
  console.error(err);
  process.exit(1);
});
