use axum::{
    extract::{Path, Query, State},
    response::Html,
    Json,
};
use bson::doc;
use futures_util::TryStreamExt;
use serde::Deserialize;

use crate::{
    auth::{verify_jwt, ApiError},
    models::{MiniAppDoc, MiniAppDto, UserDoc},
    AppState,
};

pub async fn list_active_mini_apps_handler(
    State(state): State<AppState>,
) -> Result<Json<Vec<MiniAppDto>>, ApiError> {
    let coll = state.db.collection::<MiniAppDoc>("mini_apps");
    let cursor = coll
        .find(doc! { "is_active": true })
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;
    let mut docs: Vec<MiniAppDoc> = cursor
        .try_collect()
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?;

    docs.sort_by_key(|a| a.sort_order);
    Ok(Json(docs.into_iter().map(MiniAppDto::from).collect()))
}

#[derive(Debug, Deserialize)]
pub struct MiniAppPageQuery {
    pub token: Option<String>,
    pub conv_id: Option<String>,
}

pub async fn serve_miniapp_html_handler(
    Path(code): Path<String>,
    Query(query): Query<MiniAppPageQuery>,
    State(state): State<AppState>,
) -> Html<String> {
    let token = query.token.unwrap_or_default();
    let conv_id = query
        .conv_id
        .unwrap_or_else(|| "conv_group_office".to_string());

    let mut user_display = "ผู้ใช้งาน BC Super App".to_string();
    let mut user_email = "".to_string();

    if !token.is_empty() {
        if let Ok(claims) = verify_jwt(&token, &state.config.jwt_secret) {
            user_email = claims.email.clone();
            let users_coll = state.db.collection::<UserDoc>("users");
            if let Ok(Some(u)) = users_coll.find_one(doc! { "_id": &claims.sub }).await {
                user_display = format!("{} ({})", u.display_name, u.bc_id);
            }
        }
    }

    let (title, badge_color, subtitle, field1_label, field1_default, field2_label, field2_default, amount_label, amount_default) =
        match code.as_str() {
            "ai" | "ai_copilot" => (
                "สมองกล DeepSeek AI ผู้ช่วยองค์กร",
                "#4F46E5",
                "สรุปการประชุมกลุ่ม แกะ Action Items และส่งการ์ดสรุปงานเข้าห้องแชท",
                "หัวข้อสรุปงาน / มติที่ประชุม",
                "สรุปแผนงานประจำสัปดาห์และรายการเอกสารสำคัญ",
                "Action Items ที่มอบหมาย",
                "ฝ่ายขายส่งใบเสนอราคา • ฝ่ายบัญชีตรวจใบกำกับภาษีในคลังถาวร",
                "สถานะการประมวลผล AI",
                "วิเคราะห์ด้วย DeepSeek AI สำเร็จ",
            ),
            "leave" | "leave_approval" => (
                "อนุมัติใบลา / งานบุคคล",
                "#06C755",
                "สร้างคำขออนุมัติใบลาและส่ง Rich Card เข้าห้องแชททันที",
                "ประเภทการลา",
                "ลาพักร้อนประจำปี (2 วัน)",
                "วันที่ขอลา / เหตุผล",
                "15-16 พ.ย. 2026 (เดินทางต่างจังหวัด)",
                "จำนวนวันลา",
                "2 วัน",
            ),
            "quotation" | "quick_quotation" => (
                "ออกใบเสนอราคาด่วน (Quick Quotation)",
                "#00B900",
                "สร้างใบเสนอราคาและแชร์การ์ดให้ลูกค้าหรือทีมขายในแชท",
                "ชื่อลูกค้า / บริษัท",
                "บจก. สยามซัพพลาย เทรดดิ้ง",
                "รายการสินค้า / บริการ",
                "ชุดระบบ BC Super App Enterprise (รายปี)",
                "ยอดสุทธิ (รวม VAT)",
                "48,150.00 บาท",
            ),
            "expense" | "expense_claim" => (
                "เบิกค่าใช้จ่าย / แนบบิลถาวร",
                "#0288D1",
                "บันทึกใบเบิกค่าใช้จ่ายพร้อมเก็บหลักฐานถาวรบน MinIO ไม่หมดอายุ",
                "หมวดหมู่ค่าใช้จ่าย",
                "ค่ารับรองลูกค้า / ค่าเดินทาง",
                "รายละเอียดอ้างอิงบิล",
                "ใบกำกับภาษีเลขที่ INV-2026-00912",
                "จำนวนเงินเบิกสุทธิ",
                "3,450.00 บาท",
            ),
            "booking" | "crm_queue" => (
                "จองคิว / นัดหมายลูกค้า (CRM Queue)",
                "#7B1FA2",
                "ส่งการ์ดยืนยันเวลานัดหมายเข้าห้องแชทให้ลูกค้าทราบทันที",
                "ชื่อลูกค้า / ผู้ติดต่อ",
                "คุณกิตติพงศ์ (ฝ่ายจัดซื้อ)",
                "วัน-เวลานัดหมาย & สถานที่",
                "พรุ่งนี้ เวลา 14:00 น. (ห้องประชุมออนไลน์ / โชว์รูม)",
                "สถานะคิวนัดหมาย",
                "ยืนยันคิว #Q-108",
            ),
            _ => (
                "บริการเสริม BC Mini-App",
                "#06C755",
                "ระบบ WebView Mini-App เชื่อมต่อแชทด้วย JS Bridge",
                "หัวข้อรายการ",
                "แจ้งข้อมูลบริการเสริม",
                "รายละเอียด",
                "ส่งข้อมูลจากระบบ Mini-App เข้าห้องแชท",
                "ข้อมูลอ้างอิง / ยอดรวม",
                "สำเร็จ 100%",
            ),
        };

    let html = format!(
        r##"<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{title} - BC Mini-App</title>
  <style>
    * {{ box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans Thai", sans-serif; }}
    body {{ margin: 0; padding: 16px; background: #F1F5F9; color: #0F172A; }}
    .card {{ max-width: 520px; margin: 0 auto; background: #FFFFFF; border-radius: 16px; box-shadow: 0 4px 20px rgba(15, 23, 42, 0.08); overflow: hidden; }}
    .header {{ background: {badge_color}; color: #FFFFFF; padding: 18px 20px; }}
    .header h1 {{ margin: 0; font-size: 19px; font-weight: 700; }}
    .header p {{ margin: 6px 0 0; font-size: 13px; opacity: 0.92; }}
    .sso-bar {{ background: #F8FAFC; padding: 10px 20px; border-bottom: 1px solid #E2E8F0; font-size: 13px; color: #334155; display: flex; justify-content: space-between; align-items: center; }}
    .sso-badge {{ background: #DCFCE7; color: #166534; padding: 3px 8px; border-radius: 999px; font-weight: 600; font-size: 11px; }}
    .body {{ padding: 20px; }}
    .form-group {{ margin-bottom: 14px; }}
    label {{ display: block; font-size: 13px; font-weight: 600; color: #334155; margin-bottom: 6px; }}
    input, select, textarea {{ width: 100%; padding: 10px 12px; border: 1px solid #CBD5E1; border-radius: 10px; font-size: 14px; color: #0F172A; outline: none; }}
    input:focus, select:focus, textarea:focus {{ border-color: {badge_color}; box-shadow: 0 0 0 3px rgba(6, 199, 85, 0.15); }}
    .btn {{ width: 100%; padding: 13px 16px; border: none; border-radius: 12px; background: {badge_color}; color: #FFFFFF; font-size: 15px; font-weight: 700; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 8px; }}
    .btn:hover {{ opacity: 0.94; }}
    .status-box {{ margin-top: 14px; padding: 12px; border-radius: 10px; font-size: 13px; display: none; }}
    .status-ok {{ background: #DCFCE7; color: #166534; border: 1px solid #86EFAC; display: block; }}
    .status-err {{ background: #FEE2E2; color: #991B1B; border: 1px solid #FCA5A5; display: block; }}
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <h1>{title}</h1>
      <p>{subtitle}</p>
    </div>
    <div class="sso-bar">
      <span>ผู้ใช้งาน SSO: <strong>{user_display}</strong> {user_email}</span>
      <span class="sso-badge">Gmail SSO เชื่อมต่อแล้ว</span>
    </div>
    <div class="body">
      <div class="form-group">
        <label>เลือกห้องแชทปลายทางที่จะส่งการ์ด</label>
        <select id="convSelect">
          <option value="{conv_id}">ห้องแชทปัจจุบัน ({conv_id})</option>
        </select>
      </div>
      <div class="form-group">
        <label>{field1_label}</label>
        <input id="field1" type="text" value="{field1_default}" />
      </div>
      <div class="form-group">
        <label>{field2_label}</label>
        <input id="field2" type="text" value="{field2_default}" />
      </div>
      <div class="form-group">
        <label>{amount_label}</label>
        <input id="amount" type="text" value="{amount_default}" />
      </div>
      <button class="btn" onclick="sendFlexCard()">
        <span>ส่งการ์ดเข้าห้องแชททันที</span>
      </button>
      <div id="statusBox" class="status-box"></div>
    </div>
  </div>

  <script>
    const TOKEN = {token_json};
    const DEFAULT_CONV_ID = {conv_id_json};
    const APP_CODE = {code_json};
    const APP_TITLE = {title_json};
    const BADGE_COLOR = {color_json};

    async function loadRooms() {{
      if (!TOKEN) return;
      try {{
        const res = await fetch('/api/conversations?folder=all', {{
          headers: {{ 'Authorization': 'Bearer ' + TOKEN }}
        }});
        if (!res.ok) return;
        const rooms = await res.json();
        const sel = document.getElementById('convSelect');
        sel.innerHTML = '';
        rooms.forEach(r => {{
          const opt = document.createElement('option');
          opt.value = r.id;
          opt.textContent = (r.type === 'group' ? '👥 ' : '💬 ') + r.name;
          if (r.id === DEFAULT_CONV_ID) opt.selected = true;
          sel.appendChild(opt);
        }});
      }} catch (e) {{
        console.warn(e);
      }}
    }}

    async function sendFlexCard() {{
      const convId = document.getElementById('convSelect').value || DEFAULT_CONV_ID;
      const f1 = document.getElementById('field1').value;
      const f2 = document.getElementById('field2').value;
      const amt = document.getElementById('amount').value;
      const statusBox = document.getElementById('statusBox');

      const flexPayload = {{
        app_code: APP_CODE,
        title: APP_TITLE,
        color_hex: BADGE_COLOR,
        heading: f1,
        subtitle: f2,
        highlight_value: amt,
        status_label: "อนุมัติ / ยืนยันแล้ว",
        action_url: window.location.href
      }};

      try {{
        const res = await fetch('/api/conversations/' + encodeURIComponent(convId) + '/messages', {{
          method: 'POST',
          headers: {{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + TOKEN
          }},
          body: JSON.stringify({{
            type: 'flex_card',
            content: '[' + APP_TITLE + '] ' + f1 + ' — ' + amt,
            flex_payload: flexPayload
          }})
        }});

        if (!res.ok) throw new Error('HTTP ' + res.status);
        const msg = await res.json();
        statusBox.className = 'status-box status-ok';
        statusBox.textContent = '✅ ส่งการ์ดเข้าห้องแชทเรียบร้อยแล้ว! (รหัสข้อความ: ' + msg.id.slice(0, 8) + ')';

        if (window.parent && window.parent !== window) {{
          window.parent.postMessage({{
            event: 'miniapp_card_sent',
            conversation_id: convId,
            message: msg
          }}, '*');
        }}
      }} catch (err) {{
        statusBox.className = 'status-box status-err';
        statusBox.textContent = '❌ ไม่สามารถส่งการ์ดได้: ' + err.message;
      }}
    }}

    loadRooms();
  </script>
</body>
</html>"##,
        title = title,
        badge_color = badge_color,
        subtitle = subtitle,
        user_display = user_display,
        user_email = if user_email.is_empty() {
            "".to_string()
        } else {
            format!("• {}", user_email)
        },
        conv_id = conv_id,
        field1_label = field1_label,
        field1_default = field1_default,
        field2_label = field2_label,
        field2_default = field2_default,
        amount_label = amount_label,
        amount_default = amount_default,
        token_json = serde_json::to_string(&token).unwrap_or_else(|_| "\"\"".to_string()),
        conv_id_json = serde_json::to_string(&conv_id).unwrap_or_else(|_| "\"\"".to_string()),
        code_json = serde_json::to_string(&code).unwrap_or_else(|_| "\"\"".to_string()),
        title_json = serde_json::to_string(&title).unwrap_or_else(|_| "\"\"".to_string()),
        color_json = serde_json::to_string(&badge_color).unwrap_or_else(|_| "\"#06C755\"".to_string()),
    );

    Html(html)
}
