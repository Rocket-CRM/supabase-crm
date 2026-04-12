import { addPropertyControls, ControlType } from "framer"
import React, { CSSProperties, useRef, useState, useEffect } from "react"

// ============================================================================
// TYPES
// ============================================================================

interface Props {
    header1: string
    paragraph1: string
    header2: string
    paragraph2: string
    header3: string
    paragraph3: string
    header4: string
    paragraph4: string
    header5: string
    paragraph5: string
    header6: string
    paragraph6: string
    header7: string
    paragraph7: string
    header8: string
    paragraph8: string
    headerFont: Record<string, any>
    headerFontSize: number
    headerColor: string
    paragraphFont: Record<string, any>
    paragraphFontSize: number
    paragraphColor: string
    dividerColor: string
    iconColor: string
    style?: CSSProperties
}

// ============================================================================
// HELPERS
// ============================================================================

const VARIANT_TO_WEIGHT: Record<string, number> = {
    Thin: 100,
    "Extra Light": 200,
    Light: 300,
    Regular: 400,
    Medium: 500,
    Semibold: 600,
    Bold: 700,
    "Extra Bold": 800,
    Black: 900,
    "Thin Italic": 100,
    "Extra Light Italic": 200,
    "Light Italic": 300,
    Italic: 400,
    "Regular Italic": 400,
    "Medium Italic": 500,
    "Semibold Italic": 600,
    "Bold Italic": 700,
    "Extra Bold Italic": 800,
    "Black Italic": 900,
}

function resolveFontStyle(
    font: Record<string, any>,
    explicitSize: number,
    color: string,
    weightOverride?: number
): CSSProperties {
    const { variant, fontStyle: _fs, ...rest } = font ?? {}
    const fontWeight = weightOverride
        ? weightOverride
        : variant
          ? (VARIANT_TO_WEIGHT[variant] ?? 400)
          : (rest.fontWeight ?? 400)
    const isItalic =
        typeof variant === "string" && variant.toLowerCase().includes("italic")
    const fallbackFamily =
        "Inter, -apple-system, BlinkMacSystemFont, sans-serif"
    return {
        fontFamily: fallbackFamily,
        lineHeight: 1.6,
        letterSpacing: "-0.01em",
        ...rest,
        fontWeight,
        fontStyle: isItalic ? "italic" : "normal",
        fontSize: explicitSize,
        color,
    }
}

// ============================================================================
// DEFAULTS
// ============================================================================

const DEFAULTS = [
    {
        header: "ระบบสะสมแต้มคืออะไร?",
        paragraph:
            "ระบบสะสมแต้ม คือเครื่องมือที่ให้แบรนด์มอบคะแนนให้ลูกค้าจากยอดซื้อหรือพฤติกรรมอื่นๆ ลูกค้านำคะแนนไปแลกรางวัล คูปอง หรือสิทธิพิเศษ ระบบสะสมแต้มยุคใหม่อย่าง Rocket เป็นมากกว่าแค่ให้คะแนน — รวมถึงระบบ CRM ที่เก็บข้อมูลลูกค้า แบ่งระดับสมาชิก สร้างแคมเปญ และใช้ AI ส่งข้อเสนอเฉพาะบุคคลอัตโนมัติ",
    },
    {
        header: "ระบบสะสมแต้มต่างจากระบบ CRM อย่างไร?",
        paragraph:
            "CRM เน้นจัดการข้อมูลลูกค้าและการสื่อสาร ส่วนระบบสะสมแต้มเน้นสร้างแรงจูงใจผ่านคะแนนและรางวัล Rocket รวมทั้งสองระบบไว้ในแพลตฟอร์มเดียว",
    },
    {
        header: "ระบบสะสมแต้มทำอะไรได้บ้าง?",
        paragraph:
            "สะสมแต้มจากการซื้อสินค้า แลกรางวัล คูปอง สิทธิพิเศษ แบ่งระดับสมาชิก สร้างแคมเปญโปรโมชัน ติดตามพฤติกรรมลูกค้า และวิเคราะห์ข้อมูลเพื่อเพิ่มยอดขาย",
    },
    {
        header: "ระบบสะสมแต้มเหมาะกับธุรกิจแบบไหน?",
        paragraph:
            "เหมาะกับทุกธุรกิจที่มีลูกค้าซื้อซ้ำ เช่น ร้านอาหาร คาเฟ่ ร้านค้าปลีก คลินิกความงาม ฟิตเนส และธุรกิจบริการทุกประเภท",
    },
    {
        header: "Rocket ต่างจากระบบสะสมแต้มตัวอื่นอย่างไร?",
        paragraph:
            "Rocket รวม CRM + Loyalty + AI ไว้ในแพลตฟอร์มเดียว ไม่ต้องใช้หลายระบบ มีฟีเจอร์ครบตั้งแต่สะสมแต้ม แบ่งเทียร์ สร้างแคมเปญ ไปจนถึง AI วิเคราะห์พฤติกรรมลูกค้า",
    },
    {
        header: "Loyalty Program กับระบบ CRM ต่างกันไหม?",
        paragraph:
            "Loyalty Program เน้นสร้างความภักดีผ่านรางวัลและสิทธิพิเศษ ส่วน CRM เน้นจัดการความสัมพันธ์กับลูกค้าในภาพรวม Rocket รวมทั้งสองไว้ด้วยกัน",
    },
    {
        header: "ใช้เวลานานแค่ไหนถึงเริ่มใช้ระบบสะสมแต้มได้?",
        paragraph:
            "สามารถเริ่มต้นใช้งานได้ภายใน 1-2 สัปดาห์ ขึ้นอยู่กับความซับซ้อนของธุรกิจและจำนวนสาขา ทีมงานจะช่วยตั้งค่าและอบรมการใช้งานให้",
    },
    {
        header: "ลูกค้าต้องโหลดแอปเพิ่มไหม?",
        paragraph:
            "ไม่จำเป็น ลูกค้าสามารถใช้งานผ่าน LINE OA หรือเว็บแอปได้เลย ไม่ต้องดาวน์โหลดแอปเพิ่ม สะดวกทั้งร้านค้าและลูกค้า",
    },
]

// ============================================================================
// SINGLE ACCORDION ITEM
// ============================================================================

interface AccordionItemProps {
    header: string
    paragraph: string
    isOpen: boolean
    onToggle: () => void
    headerStyle: CSSProperties
    paragraphStyle: CSSProperties
    dividerColor: string
    iconColor: string
    isLast: boolean
    isMobile: boolean
}

function AccordionItem({
    header,
    paragraph,
    isOpen,
    onToggle,
    headerStyle,
    paragraphStyle,
    dividerColor,
    iconColor,
    isLast,
    isMobile,
}: AccordionItemProps) {
    const contentRef = useRef<HTMLDivElement>(null)
    const [contentHeight, setContentHeight] = useState(0)

    useEffect(() => {
        if (contentRef.current) {
            setContentHeight(contentRef.current.scrollHeight)
        }
    }, [paragraph, isOpen])

    return (
        <div
            style={{
                borderBottom: isLast ? "none" : `1px solid ${dividerColor}`,
            }}
        >
            <button
                onClick={onToggle}
                aria-expanded={isOpen}
                style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    width: "100%",
                    padding: isMobile ? "20px 0" : "28px 0",
                    background: "none",
                    border: "none",
                    cursor: "pointer",
                    textAlign: "left",
                    gap: 16,
                }}
            >
                <h3
                    style={{
                        margin: 0,
                        flex: 1,
                        ...headerStyle,
                        fontSize: isMobile
                            ? Math.max(headerStyle.fontSize as number - 4, 14)
                            : headerStyle.fontSize,
                    }}
                >
                    {header}
                </h3>
                <div
                    style={{
                        width: 28,
                        height: 28,
                        flexShrink: 0,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                    }}
                >
                    <svg
                        width="20"
                        height="20"
                        viewBox="0 0 20 20"
                        fill="none"
                    >
                        <path
                            d="M4 10H16"
                            stroke={iconColor}
                            strokeWidth="2"
                            strokeLinecap="round"
                        />
                        <path
                            d="M10 4V16"
                            stroke={iconColor}
                            strokeWidth="2"
                            strokeLinecap="round"
                            style={{
                                transition: "opacity 0.3s ease",
                                opacity: isOpen ? 0 : 1,
                            }}
                        />
                    </svg>
                </div>
            </button>

            <div
                style={{
                    overflow: "hidden",
                    transition: "max-height 0.35s ease, opacity 0.3s ease",
                    maxHeight: isOpen ? contentHeight + 24 : 0,
                    opacity: isOpen ? 1 : 0,
                }}
            >
                <div ref={contentRef}>
                    <p
                        style={{
                            margin: 0,
                            paddingBottom: isMobile ? 20 : 28,
                            maxWidth: 720,
                            ...paragraphStyle,
                            fontSize: isMobile
                                ? Math.max(
                                      paragraphStyle.fontSize as number - 2,
                                      13
                                  )
                                : paragraphStyle.fontSize,
                        }}
                    >
                        {paragraph}
                    </p>
                </div>
            </div>
        </div>
    )
}

// ============================================================================
// MAIN COMPONENT
// ============================================================================

/**
 * @framerDisableUnlink
 *
 * @framerIntrinsicWidth 800
 * @framerIntrinsicHeight 600
 *
 * @framerSupportedLayoutWidth any-prefer-fixed
 * @framerSupportedLayoutHeight any
 */
export default function FAQAccordion(props: Props) {
    const {
        header1,
        paragraph1,
        header2,
        paragraph2,
        header3,
        paragraph3,
        header4,
        paragraph4,
        header5,
        paragraph5,
        header6,
        paragraph6,
        header7,
        paragraph7,
        header8,
        paragraph8,
        headerFont = {},
        headerFontSize = 20,
        headerColor = "#FFFFFF",
        paragraphFont = {},
        paragraphFontSize = 16,
        paragraphColor = "#CCCCCC",
        dividerColor = "rgba(255,255,255,0.15)",
        iconColor = "#FFFFFF",
        style,
    } = props

    const containerRef = useRef<HTMLDivElement>(null)
    const [openIndex, setOpenIndex] = useState<number | null>(0)
    const [isMobile, setIsMobile] = useState(false)

    useEffect(() => {
        const el = containerRef.current
        if (!el) return
        const observer = new ResizeObserver((entries) => {
            for (const entry of entries) {
                setIsMobile(entry.contentRect.width <= 600)
            }
        })
        observer.observe(el)
        return () => observer.disconnect()
    }, [])

    const allItems = [
        { header: header1, paragraph: paragraph1, fallback: DEFAULTS[0] },
        { header: header2, paragraph: paragraph2, fallback: DEFAULTS[1] },
        { header: header3, paragraph: paragraph3, fallback: DEFAULTS[2] },
        { header: header4, paragraph: paragraph4, fallback: DEFAULTS[3] },
        { header: header5, paragraph: paragraph5, fallback: DEFAULTS[4] },
        { header: header6, paragraph: paragraph6, fallback: DEFAULTS[5] },
        { header: header7, paragraph: paragraph7, fallback: DEFAULTS[6] },
        { header: header8, paragraph: paragraph8, fallback: DEFAULTS[7] },
    ]

    const items = allItems
        .filter((item) => {
            const h = item.header?.trim()
            const p = item.paragraph?.trim()
            return h || p
        })
        .map((item) => ({
            header: item.header?.trim() || item.fallback.header,
            paragraph: item.paragraph?.trim() || item.fallback.paragraph,
        }))

    const headerStyle = resolveFontStyle(headerFont, headerFontSize, headerColor, 700)
    const paragraphStyle = resolveFontStyle(paragraphFont, paragraphFontSize, paragraphColor)

    const handleToggle = (index: number) => {
        setOpenIndex((prev) => (prev === index ? null : index))
    }

    return (
        <div
            ref={containerRef}
            style={{
                ...style,
                width: "100%",
                boxSizing: "border-box",
                padding: isMobile ? "0 16px" : "0",
            }}
        >
            <div
                style={{
                    width: "100%",
                    borderTop: items.length > 0 ? `1px solid ${dividerColor}` : "none",
                }}
            >
                {items.map((item, i) => (
                    <AccordionItem
                        key={i}
                        header={item.header}
                        paragraph={item.paragraph}
                        isOpen={openIndex === i}
                        onToggle={() => handleToggle(i)}
                        headerStyle={headerStyle}
                        paragraphStyle={paragraphStyle}
                        dividerColor={dividerColor}
                        iconColor={iconColor}
                        isLast={i === items.length - 1}
                        isMobile={isMobile}
                    />
                ))}
            </div>
        </div>
    )
}

// ============================================================================
// DEFAULT PROPS
// ============================================================================

FAQAccordion.defaultProps = {
    header1: DEFAULTS[0].header,
    paragraph1: DEFAULTS[0].paragraph,
    header2: DEFAULTS[1].header,
    paragraph2: DEFAULTS[1].paragraph,
    header3: DEFAULTS[2].header,
    paragraph3: DEFAULTS[2].paragraph,
    header4: DEFAULTS[3].header,
    paragraph4: DEFAULTS[3].paragraph,
    header5: DEFAULTS[4].header,
    paragraph5: DEFAULTS[4].paragraph,
    header6: DEFAULTS[5].header,
    paragraph6: DEFAULTS[5].paragraph,
    header7: DEFAULTS[6].header,
    paragraph7: DEFAULTS[6].paragraph,
    header8: DEFAULTS[7].header,
    paragraph8: DEFAULTS[7].paragraph,
    headerFont: {},
    headerFontSize: 20,
    headerColor: "#FFFFFF",
    paragraphFont: {},
    paragraphFontSize: 16,
    paragraphColor: "#CCCCCC",
    dividerColor: "rgba(255,255,255,0.15)",
    iconColor: "#FFFFFF",
}

// ============================================================================
// PROPERTY CONTROLS
// ============================================================================

function faqControls(n: number) {
    return {
        [`header${n}`]: {
            type: ControlType.String,
            title: `FAQ ${n} Header`,
            placeholder: `Question ${n}...`,
        },
        [`paragraph${n}`]: {
            type: ControlType.String,
            title: `FAQ ${n} Answer`,
            placeholder: `Answer ${n}...`,
            displayTextArea: true,
        },
    }
}

addPropertyControls(FAQAccordion, {
    ...faqControls(1),
    ...faqControls(2),
    ...faqControls(3),
    ...faqControls(4),
    ...faqControls(5),
    ...faqControls(6),
    ...faqControls(7),
    ...faqControls(8),
    // Typography — Header
    headerFont: {
        type: ControlType.Font,
        title: "Header Font",
        controls: "extended",
        displayFontSize: false,
        defaultFontType: "sans-serif",
    },
    headerFontSize: {
        type: ControlType.Number,
        title: "Header Size",
        min: 14,
        max: 48,
        step: 1,
        defaultValue: 20,
        unit: "px",
        displayStepper: true,
    },
    headerColor: {
        type: ControlType.Color,
        title: "Header Color",
        defaultValue: "#FFFFFF",
    },
    // Typography — Paragraph
    paragraphFont: {
        type: ControlType.Font,
        title: "Answer Font",
        controls: "extended",
        displayFontSize: false,
        defaultFontType: "sans-serif",
    },
    paragraphFontSize: {
        type: ControlType.Number,
        title: "Answer Size",
        min: 12,
        max: 36,
        step: 1,
        defaultValue: 16,
        unit: "px",
        displayStepper: true,
    },
    paragraphColor: {
        type: ControlType.Color,
        title: "Answer Color",
        defaultValue: "#CCCCCC",
    },
    // Divider & Icon
    dividerColor: {
        type: ControlType.Color,
        title: "Divider Color",
        defaultValue: "rgba(255,255,255,0.15)",
    },
    iconColor: {
        type: ControlType.Color,
        title: "Icon Color",
        defaultValue: "#FFFFFF",
    },
})
