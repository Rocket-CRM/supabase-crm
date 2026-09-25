#!/usr/bin/env python3
"""Fill Appendix B forms from CSV details + decided project roles, then export PDFs."""

from __future__ import annotations

import html
import subprocess
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent / "appendix-b"
PDF_DIR = OUT_DIR / "pdf"
DOWNLOADS = Path.home() / "Downloads" / "eeco-appendix-b-pdf"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROJECT = (
    "การพัฒนาระบบบริหารจัดการความสัมพันธ์นักลงทุนและฐานข้อมูลกลาง "
    "(CRM & Database Management System)"
)
SIGNATORY = "มัลลิกา กุลนาพันธ์"
ROCKET = "บริษัท ร็อคเก็ต อินโนเวชั่น จำกัด (Rocket Innovation Co., Ltd.)"

# Decided project roles (TOR + additional). Rocket title combined when different.
PERSONNEL = [
    {
        "file_name": "Varapong-Techapanichgul_Project-Manager",
        "thai_name": "วราพงศ์ เตชะพานิชกุล",
        "en_name": "Varapong Techapanichgul",
        "project_role": "ผู้จัดการโครงการ (Project Manager)",
        "duties": "กำกับการส่งมอบโครงการ กำหนดทิศทางเชิงเทคนิค บริหารงวดงาน และเป็นจุดติดต่อหลักด้านการดำเนินงานกับ สกพอ.",
        "education": [
            {
                "institution": "Parsons School of Design",
                "degree": "ปริญญาโท",
                "major": "MFA Digital and Technology",
                "start": "2560",
                "end": "2562",
            },
            {
                "institution": "จุฬาลงกรณ์มหาวิทยาลัย (Chulalongkorn University)",
                "degree": "ปริญญาตรี",
                "major": "Bachelor of Fine and Applied Arts",
                "start": "2553",
                "end": "2556",
            },
        ],
        "experience": [
            {"org": "Apple Inc., Sunnyvale, California", "start": "2562", "end": "2564", "title": "Front end Technologist"},
            {"org": "100X, Bangkok, Thailand", "start": "2564", "end": "2566", "title": "Technical Artist"},
            {"org": ROCKET, "start": "2567", "end": "ปัจจุบัน", "title": "ผู้จัดการโครงการ (Project Manager) & Engineer"},
        ],
    },
    {
        "file_name": "Ekasit-Jatupornwattana_Business-Analyst",
        "thai_name": "เอกสิทธิ์ จตุพรวัฒนา",
        "en_name": "Ekasit Jatupornwattana",
        "project_role": "นักวิเคราะห์ระบบ (Business Analyst)",
        "duties": "จัดทำ BRD กำหนด workflow ถ่ายทอดความต้องการสู่การออกแบบและพัฒนา และติดตามความสอดคล้องตลอดวงจรโครงการ",
        "education": [
            {
                "institution": "มหาวิทยาลัยเอเชียอาคเนย์ (Southeast Asia University)",
                "degree": "ปริญญาตรี",
                "major": "Computer Science",
                "start": "2544",
                "end": "2547",
            },
        ],
        "experience": [
            {"org": "Vision square", "start": "2548", "end": "2552", "title": "System Analyst"},
            {"org": "Itos", "start": "2553", "end": "2554", "title": "System Analyst"},
            {"org": "Hyro asia", "start": "2554", "end": "2557", "title": "System Analyst"},
            {"org": "Issoft", "start": "2558", "end": "2564", "title": "System Analyst"},
            {"org": "MI group", "start": "2564", "end": "2564", "title": "System Analyst"},
            {"org": ROCKET, "start": "2565", "end": "ปัจจุบัน", "title": "นักวิเคราะห์ระบบ (Business Analyst) & System Analyst"},
        ],
    },
    {
        "file_name": "Thitawan-Hirunurann_Senior-System-Analyst",
        "thai_name": "ฐิตวันต์ หิรัณย์อุฬาร",
        "en_name": "Thitawan Hirunurann",
        "project_role": "นักออกแบบระบบอาวุโส (Senior System Analyst)",
        "duties": "ออกแบบ UI/UX หน้าจอสำหรับเจ้าหน้าที่ รองรับมือถือ สร้าง prototype และปรับปรุงประสบการณ์การใช้งาน",
        "education": [
            {
                "institution": "มหาวิทยาลัยศิลปากร (Silpakorn University)",
                "degree": "ปริญญาตรี",
                "major": "(ICT) Information and Communication Technology",
                "start": "2557",
                "end": "2561",
            },
        ],
        "experience": [
            {"org": "The real one", "start": "2561", "end": "2562", "title": "Junior UX/UI designer"},
            {"org": "Pandasoft & Development", "start": "2563", "end": "2564", "title": "Junior UX/UI designer"},
            {"org": "Iconkaset", "start": "2564", "end": "2565", "title": "Mid level UX/UI designer"},
            {"org": ROCKET, "start": "2565", "end": "2566", "title": "Senior UX/UI designer"},
            {"org": "Big Data Agency", "start": "2566", "end": "2566", "title": "Product manager & Lead UX/UI designer"},
            {
                "org": ROCKET,
                "start": "2566",
                "end": "ปัจจุบัน",
                "title": "นักออกแบบระบบอาวุโส (Senior System Analyst) & Designer",
            },
        ],
    },
    {
        "file_name": "Thammarong-Kikasemsri_Senior-Developer",
        "thai_name": "ธรรมรงค์ กีเกษมศรี",
        "en_name": "Thammarong Kikasemsri",
        "project_role": "นักพัฒนาระบบอาวุโส (Senior Developer)",
        "duties": "กำกับการพัฒนาระบบ CRM หลัก ทบทวนโค้ด บูรณาการ API และคุณภาพการส่งมอบ",
        "education": [
            {
                "institution": "มหาวิทยาลัยเทคโนโลยีพระจอมเกล้าพระนครเหนือ (KMUTNB)",
                "degree": "ปริญญาตรี",
                "major": "Computer Science",
                "start": "2556",
                "end": "2560",
            },
        ],
        "experience": [
            {"org": "Streaming Co., Ltd", "start": "2560", "end": "2562", "title": "Full Stack Developer"},
            {"org": "ITTP CO., LTD", "start": "2562", "end": "2564", "title": "Full Stack Developer"},
            {"org": "Noburo Platform Co., Ltd", "start": "2564", "end": "2567", "title": "Full Stack Developer"},
            {"org": ROCKET, "start": "2567", "end": "ปัจจุบัน", "title": "นักพัฒนาระบบอาวุโส (Senior Developer) & Engineer"},
        ],
    },
    {
        "file_name": "Ratchapol-Hengmongkolsakul_Developer",
        "thai_name": "รัชพล เฮงมงคลสกุล",
        "en_name": "Ratchapol Hengmongkolsakul",
        "project_role": "นักพัฒนาระบบ (Developer)",
        "duties": "พัฒนาฟีเจอร์ ทดสอบหน่วย แก้ไขข้อบกพร่อง ติดตั้ง และสนับสนุนการส่งมอบ",
        "education": [
            {
                "institution": "มหาวิทยาลัยเกษตรศาสตร์ (Kasetsart University)",
                "degree": "ปริญญาตรี",
                "major": "Computer Science",
                "start": "2560",
                "end": "2564",
            },
        ],
        "experience": [
            {"org": "GOCODING CO., LTD., BANGKOK", "start": "2564", "end": "2565", "title": "Full Stack Developer"},
            {"org": "2FELLOWS NETWORK AND DESIGN CO., LTD, BANGKOK", "start": "2565", "end": "2566", "title": "Backend Developer"},
            {"org": ROCKET, "start": "2566", "end": "ปัจจุบัน", "title": "นักพัฒนาระบบ (Developer) & Engineer"},
        ],
    },
    {
        "file_name": "Assadavoot-Anukool_Project-Coordinator",
        "thai_name": "อัษฎาวุธ อนุกูล",
        "en_name": "Assadavoot Anukool",
        "project_role": "ผู้ประสานงานโครงการ (Project Coordinator)",
        "duties": "ประสานการประชุม บันทึกรายการติดตาม เอกสาร และการติดตั้ง/ส่งมอบ",
        "education": [
            {
                "institution": "มหาวิทยาลัยเทคโนโลยีมหานคร (Mahanakorn University of Technology)",
                "degree": "ปริญญาตรี",
                "major": "Computer Engineering",
                "start": "2556",
                "end": "2561",
            },
        ],
        "experience": [
            {"org": "JMT NETWORK SERVICES PUBLIC COMPANY LIMITED", "start": "2561", "end": "2563", "title": "Programmer And Developer"},
            {"org": "Natachat Company Limited", "start": "2563", "end": "2566", "title": "Full Stack Developer"},
            {
                "org": ROCKET,
                "start": "2566",
                "end": "ปัจจุบัน",
                "title": "ผู้ประสานงานโครงการ (Project Coordinator) & Engineer",
            },
        ],
    },
    {
        "file_name": "Nutnicha-Jitruttanaarun_Tester",
        "thai_name": "ณัฐณิชา จิตต์รัตนอรัญ",
        "en_name": "Nutnicha Jitruttanaarun",
        "project_role": "นักทดสอบระบบ (Tester)",
        "duties": "จัดทำและดำเนินการทดสอบ รายงานข้อบกพร่อง ทดสอบซ้ำ และจัดหลักฐานคุณภาพการส่งมอบ",
        "education": [
            {
                "institution": "สถาบันเทคโนโลยีพระจอมเกล้าเจ้าคุณทหารลาดกระบัง (KMITL)",
                "degree": "ปริญญาตรี",
                "major": "Information Technology",
                "start": "2558",
                "end": "2561",
            },
        ],
        "experience": [
            {"org": "Intelligent Bytes", "start": "2562", "end": "2564", "title": "Web Developer"},
            {"org": "RS Group", "start": "2564", "end": "2564", "title": "Frontend Programmer"},
            {"org": "2Fellow Network and Design", "start": "2564", "end": "2565", "title": "Frontend developer"},
            {"org": ROCKET, "start": "2565", "end": "ปัจจุบัน", "title": "นักทดสอบระบบ (Tester) & Engineer"},
        ],
    },
    {
        "file_name": "Kritsana-Tanwised_Senior-Tester",
        "thai_name": "กฤษณะ ฐานวิเศษ",
        "en_name": "Kritsana Tanwised",
        "project_role": "นักทดสอบระบบอาวุโส (Senior Tester)",
        "duties": "กำหนดกลยุทธ์การทดสอบ กำกับคุณภาพ และเตรียมความพร้อมรับ UAT",
        "education": [
            {
                "institution": "มหาวิทยาลัยมหาสารคาม (Mahasarakham University)",
                "degree": "ปริญญาตรี",
                "major": "Computer Science",
                "start": "2560",
                "end": "2564",
            },
        ],
        "experience": [
            {"org": "Digio (Thailand)", "start": "2564", "end": "2564", "title": "Software Tester"},
            {"org": "NIPA Technology", "start": "2564", "end": "2565", "title": "Software Quality Assurance"},
            {"org": "Buzzebees", "start": "2565", "end": "2566", "title": "Software Quality Assurance"},
            {"org": ROCKET, "start": "2566", "end": "ปัจจุบัน", "title": "นักทดสอบระบบอาวุโส (Senior Tester) & Quality Assurance"},
        ],
    },
    {
        "file_name": "Prakan-Pojpienlert_Programme-Coordinator",
        "thai_name": "ปราการ พจน์เพียรเลิศ",
        "en_name": "Prakan Pojpienlert",
        "project_role": "ผู้ประสานงานโครงการ (Programme Coordinator)",
        "duties": "บริหารงานโครงการประจำวัน กำหนดการ ขอบเขต ความเสี่ยง รายงานสถานะ และประสานงานกับ สกพอ.",
        "education": [
            {
                "institution": "มหาวิทยาลัยปักกิ่ง (Peking University)",
                "degree": "ปริญญาตรี",
                "major": "Chinese language and literature",
                "start": "2559",
                "end": "2563",
            },
        ],
        "experience": [
            {"org": "China Railway Construction", "start": "2563", "end": "2564", "title": "Business Development"},
            {"org": "Flash Express", "start": "2564", "end": "2566", "title": "Product Manager"},
            {"org": "Flash Express", "start": "2566", "end": "2567", "title": "Partner Operations Manager"},
            {"org": "Kerry Express", "start": "2567", "end": "2568", "title": "Business Analyst"},
            {"org": ROCKET, "start": "2568", "end": "ปัจจุบัน", "title": "ผู้ประสานงานโครงการ (Programme Coordinator) & Product Owner"},
        ],
    },
    {
        "file_name": "Teerakarn-Boriboonsub_Support-Business-Analyst",
        "thai_name": "ธีรกานต์ บริบูรณ์ทรัพย์",
        "en_name": "Teerakarn Boriboonsub",
        "project_role": "นักวิเคราะห์ระบบ (สนับสนุน) (Support Business Analyst)",
        "duties": "สนับสนุนการประชุมผู้ใช้งาน ประสานงานกับ สกพอ. และช่วยรวบรวมความต้องการร่วมกับ Lead BA",
        "education": [
            {
                "institution": "มหาวิทยาลัยปักกิ่ง (Peking University)",
                "degree": "ปริญญาโท",
                "major": "MA Finance",
                "start": "2566",
                "end": "2568",
            },
            {
                "institution": "มหาวิทยาลัยมหิดล (Mahidol University)",
                "degree": "ปริญญาตรี",
                "major": "BSc Information and Communication Technology",
                "start": "2560",
                "end": "2564",
            },
        ],
        "experience": [
            {"org": "MFEC", "start": "2564", "end": "2565", "title": "Software engineer"},
            {"org": "BingX", "start": "2568", "end": "2568", "title": "Business development manager"},
            {
                "org": ROCKET,
                "start": "2568",
                "end": "ปัจจุบัน",
                "title": "นักวิเคราะห์ระบบ (สนับสนุน) (Support Business Analyst) & Customer Success",
            },
        ],
    },
    {
        "file_name": "Warinthon-Aekjeen_Project-Coordinator-Operations",
        "thai_name": "วรินทร เอกจีน",
        "en_name": "Warinthon Aekjeen",
        "project_role": "ผู้ประสานงานโครงการรอง (Project Coordinator — operations)",
        "duties": "สนับสนุนงานธุรการ สถานที่ โลจิสติกส์ และการติดตามภายใน",
        "education": [
            {
                "institution": "มหาวิทยาลัยราชภัฏบ้านสมเด็จเจ้าพระยา",
                "degree": "ปริญญาตรี",
                "major": "Tourism industry",
                "start": "2555",
                "end": "2559",
            },
        ],
        "experience": [
            {"org": "Choco CRM", "start": "2564", "end": "2566", "title": "Customer Support Training"},
            {"org": ROCKET, "start": "2567", "end": "ปัจจุบัน", "title": "ผู้ประสานงานโครงการรอง (Project Coordinator — operations) & Customer Success"},
        ],
    },
    {
        "file_name": "Niraphat-Rakphong_Project-Coordinator-Assistant",
        "thai_name": "นิรภัฎ รักพงษ์",
        "en_name": "Niraphat Rakphong",
        "project_role": "ผู้ประสานงานโครงการ (ผู้ช่วย) (Project Coordinator Assistant)",
        "duties": "จัดการนัดหมาย บันทึกการประชุม ติดตามงาน และสนับสนุนเอกสารยื่นข้อเสนอ",
        "education": [
            {
                "institution": "วิทยาลัยอาชีวศึกษาอาชีวศิลป์",
                "degree": "ปริญญาตรี",
                "major": "Accountancy",
                "start": "2552",
                "end": "2554",
            },
        ],
        "experience": [
            {"org": "Crown Worldwide Limited", "start": "2567", "end": "2568", "title": "Coordinator"},
            {
                "org": ROCKET,
                "start": "2568",
                "end": "ปัจจุบัน",
                "title": "ผู้ประสานงานโครงการ (ผู้ช่วย) (Project Coordinator Assistant) & Customer Support",
            },
        ],
    },
]

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="th">
<head>
<meta charset="utf-8"/>
<title>ภาคผนวก ข — {en_name}</title>
<style>
@page {{ size: A4; margin: 14mm 16mm; }}
* {{ box-sizing: border-box; }}
html, body {{
  margin: 0; padding: 0;
  font-family: "TH SarabunPSK", "TH Sarabun New", "Sarabun", "Cordia New", "Tahoma", sans-serif;
  font-size: 11pt;
  line-height: 1.3;
  color: #000;
  background: #fff;
}}
.page {{ width: 178mm; margin: 0 auto; }}
.center {{ text-align: center; }}
.hdr-app {{ font-size: 13pt; font-weight: 700; margin: 0 0 2px 0; }}
.hdr-title {{ font-size: 12pt; font-weight: 700; margin: 0 0 14px 0; }}
.row {{ margin: 0 0 2px 0; }}
.sec {{ margin: 14px 0 0 0; }}
.sec-title {{ font-weight: 700; margin: 0 0 5px 0; }}
.u {{
  display: inline;
  border-bottom: 1px dotted #222;
  padding: 0 2px 1px 2px;
  white-space: pre-wrap;
}}
.blank {{
  display: inline-block;
  border-bottom: 1px dotted #222;
  min-width: 2.2em;
  height: 1em;
  vertical-align: baseline;
}}
.blank.w2 {{ min-width: 3.5em; }}
.indent {{ padding-left: 1.15em; }}
.exp-item {{ margin: 0 0 5px 0; }}
.edu-gap {{ height: 6px; }}
.cert {{ margin-top: 14px; text-align: justify; }}
.sigs {{
  display: grid;
  grid-template-columns: 1fr 1fr;
  column-gap: 16mm;
  margin-top: 18px;
}}
.sig {{ text-align: center; }}
.sig-cap {{ margin-bottom: 2px; }}
.sig-line {{
  margin: 22px 10px 4px;
  border-bottom: 1px dotted #222;
  height: 1.15em;
}}
.sig-paren {{ margin-top: 3px; }}
.sig-role {{ margin-top: 2px; font-size: 0.95em; }}
@media print {{ .page {{ width: auto; }} }}
</style>
</head>
<body>
<div class="page">
  <div class="center hdr-app">ภาคผนวก ข</div>
  <div class="center hdr-title">แบบฟอร์มแสดงคุณสมบัติและรับทราบการยื่นข้อเสนอของบุคลากร</div>

  <div class="row">โครงการ <span class="u">{project}</span></div>

  <div class="sec">
    <div class="sec-title">ประวัติบุคลากร</div>
    <div class="row">1. ข้อมูลทั่วไป &nbsp; ชื่อ-นามสกุล <span class="u">{full_name}</span>
      &nbsp;&nbsp;อายุ <span class="blank w2"></span> ปี</div>
  </div>

  <div class="sec">
    <div class="sec-title">2. ประวัติการศึกษา</div>
    {education_html}
  </div>

  <div class="sec">
    <div class="sec-title">3. ประสบการณ์</div>
    {experience_html}
  </div>

  <div class="sec">
    <div class="sec-title">4. ตำแหน่งที่จะถือครองตามโครงการนี้</div>
    <div class="indent">
      <div class="row"><span class="u">{project_role}</span></div>
      <div class="row" style="margin-top:5px">รายละเอียดของหน้าที่ / ความรับผิดชอบในโครงการนี้</div>
      <div class="row"><span class="u">{duties}</span></div>
    </div>
  </div>

  <div class="sec cert">
    <span class="sec-title">5. คำรับรอง</span>
    &nbsp;ข้าพเจ้าขอรับรองและได้ลงนามเป็นหลักฐานว่าข้อมูลเหล่านี้แสดงถึงตัวข้าพเจ้า คุณสมบัติ
    ประสบการณ์ของข้าพเจ้าอย่างแท้จริง และรับทราบการยื่นเสนองานและรับดำเนินการเมื่อได้รับการ
    พิจารณาคัดเลือก
  </div>

  <div class="sigs">
    <div class="sig">
      <div class="sig-cap">ลงชื่อ</div>
      <div class="sig-line"></div>
      <div class="sig-paren">({signatory})</div>
      <div class="sig-role">ผู้มีอำนาจลงนามหรือผู้รับมอบอำนาจ<br/>กรรมการบริษัท (Company Director)</div>
    </div>
    <div class="sig">
      <div class="sig-cap">ลงชื่อ</div>
      <div class="sig-line"></div>
      <div class="sig-paren">({thai_name})</div>
      <div class="sig-role">บุคลากรในโครงการ<br/>วันที่ .......... เดือน .......... พ.ศ. ..........</div>
    </div>
  </div>
</div>
</body>
</html>
"""


def esc(text: str) -> str:
    return html.escape(text, quote=False)


def render_education(items: list[dict]) -> str:
    parts: list[str] = []
    for i, edu in enumerate(items):
        if i:
            parts.append('<div class="edu-gap"></div>')
        parts.append(
            f"""<div class="indent">
  <div class="row">สถาบันการศึกษา <span class="u">{esc(edu["institution"])}</span></div>
  <div class="row">วุฒิการศึกษา <span class="u">{esc(edu["degree"])}</span>
    &nbsp;&nbsp;สาขาวิชา <span class="u">{esc(edu["major"])}</span></div>
  <div class="row">ปีที่เข้าศึกษา <span class="u">{esc(edu["start"])}</span>
    &nbsp;&nbsp;ปีที่จบการศึกษา <span class="u">{esc(edu["end"])}</span></div>
</div>"""
        )
    return "\n".join(parts)


def render_experience(items: list[dict]) -> str:
    parts: list[str] = []
    for exp in items:
        parts.append(
            f"""<div class="exp-item indent">
  <div class="row">องค์กร/บริษัทผู้ว่าจ้าง <span class="u">{esc(exp["org"])}</span>
    &nbsp;ปีที่ทำงาน ตั้งแต่ พ.ศ. <span class="u">{esc(exp["start"])}</span>
    &nbsp;ถึง พ.ศ. <span class="u">{esc(exp["end"])}</span></div>
  <div class="row">ตำแหน่ง <span class="u">{esc(exp["title"])}</span></div>
</div>"""
        )
    return "\n".join(parts)


def build_html(person: dict) -> str:
    return HTML_TEMPLATE.format(
        en_name=esc(person["en_name"]),
        project=esc(PROJECT),
        full_name=esc(f'{person["thai_name"]} ({person["en_name"]})'),
        education_html=render_education(person["education"]),
        experience_html=render_experience(person["experience"]),
        project_role=esc(person["project_role"]),
        duties=esc(person["duties"]),
        signatory=esc(SIGNATORY),
        thai_name=esc(person["thai_name"]),
    )


def html_to_pdf(html_path: Path, pdf_path: Path) -> None:
    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--no-pdf-header-footer",
            f"--print-to-pdf={pdf_path}",
            html_path.as_uri(),
        ],
        check=True,
        capture_output=True,
    )


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    DOWNLOADS.mkdir(parents=True, exist_ok=True)

    # Remove old nickname-based HTML forms (keep README)
    for old in OUT_DIR.glob("*.html"):
        old.unlink()

    for person in PERSONNEL:
        stem = person["file_name"]
        html_path = OUT_DIR / f"{stem}.html"
        pdf_path = PDF_DIR / f"{stem}.pdf"
        dl_path = DOWNLOADS / f"{stem}.pdf"

        html_path.write_text(build_html(person), encoding="utf-8")
        html_to_pdf(html_path, pdf_path)
        dl_path.write_bytes(pdf_path.read_bytes())
        print(f"OK  {stem}.html + .pdf")

    print(f"\n{len(PERSONNEL)} forms filled and exported.")
    print(f"HTML: {OUT_DIR}")
    print(f"PDF:  {PDF_DIR}")
    print(f"Copy: {DOWNLOADS}")


if __name__ == "__main__":
    main()
