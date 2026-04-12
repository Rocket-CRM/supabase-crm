import { addPropertyControls, ControlType, RenderTarget, useLocaleInfo } from "framer"
import React, { CSSProperties, useRef, useState, useEffect } from "react"

// ============================================================================
// TYPES
// ============================================================================

type ImageProp = string | { src: string }

interface Props {
    // --- Default (Thai) per-card fields ---
    image1: ImageProp; header1: string; label1: string
    image2: ImageProp; header2: string; label2: string
    image3: ImageProp; header3: string; label3: string
    image4: ImageProp; header4: string; label4: string
    image5: ImageProp; header5: string; label5: string
    image6: ImageProp; header6: string; label6: string
    // --- EN overrides ---
    image1_en: ImageProp; header1_en: string; label1_en: string
    image2_en: ImageProp; header2_en: string; label2_en: string
    image3_en: ImageProp; header3_en: string; label3_en: string
    image4_en: ImageProp; header4_en: string; label4_en: string
    image5_en: ImageProp; header5_en: string; label5_en: string
    image6_en: ImageProp; header6_en: string; label6_en: string
    // --- ZH overrides ---
    image1_zh: ImageProp; header1_zh: string; label1_zh: string
    image2_zh: ImageProp; header2_zh: string; label2_zh: string
    image3_zh: ImageProp; header3_zh: string; label3_zh: string
    image4_zh: ImageProp; header4_zh: string; label4_zh: string
    image5_zh: ImageProp; header5_zh: string; label5_zh: string
    image6_zh: ImageProp; header6_zh: string; label6_zh: string
    // --- JA overrides ---
    image1_ja: ImageProp; header1_ja: string; label1_ja: string
    image2_ja: ImageProp; header2_ja: string; label2_ja: string
    image3_ja: ImageProp; header3_ja: string; label3_ja: string
    image4_ja: ImageProp; header4_ja: string; label4_ja: string
    image5_ja: ImageProp; header5_ja: string; label5_ja: string
    image6_ja: ImageProp; header6_ja: string; label6_ja: string
    // --- Editing helper (not rendered) ---
    editLocale: string
    // --- Tile styling ---
    tileBg: string
    tileBorderColor: string
    // --- Grid spacing ---
    columnGap: number
    rowGap: number
    // --- Typography ---
    labelFont: Record<string, any>
    labelFontSize: number
    labelColor: string
    headerFontSize: number
    headerColor: string
    style?: CSSProperties
}

// ============================================================================
// HELPERS
// ============================================================================

const resolveImageSrc = (
    src: string | { src: string } | undefined | null
): string => {
    if (!src) return ""
    if (typeof src === "string") return src
    return (src as { src: string }).src ?? ""
}

const VARIANT_TO_WEIGHT: Record<string, number> = {
    Thin: 100, "Extra Light": 200, Light: 300, Regular: 400, Medium: 500,
    Semibold: 600, Bold: 700, "Extra Bold": 800, Black: 900,
    "Thin Italic": 100, "Extra Light Italic": 200, "Light Italic": 300,
    Italic: 400, "Regular Italic": 400, "Medium Italic": 500,
    "Semibold Italic": 600, "Bold Italic": 700, "Extra Bold Italic": 800,
    "Black Italic": 900,
}

function resolveFontStyle(
    font: Record<string, any>,
    explicitSize: number,
    color: string
): CSSProperties {
    const { variant, fontStyle: _fs, ...rest } = font ?? {}
    const fontWeight = variant
        ? (VARIANT_TO_WEIGHT[variant] ?? 400)
        : (rest.fontWeight ?? 600)
    const isItalic =
        typeof variant === "string" && variant.toLowerCase().includes("italic")
    const fallbackFamily =
        "Inter, -apple-system, BlinkMacSystemFont, sans-serif"
    return {
        fontFamily: fallbackFamily,
        lineHeight: 1.75,
        letterSpacing: "-0.03125em",
        textAlign: "center" as const,
        ...rest,
        fontWeight,
        fontStyle: isItalic ? "italic" : "normal",
        fontSize: explicitSize,
        color,
    }
}

const LOCALE_SUFFIXES = ["en", "zh", "ja"] as const

function resolveLocaleKey(localeCode: string | undefined): string | null {
    if (!localeCode) return null
    const lc = localeCode.toLowerCase()
    for (const suffix of LOCALE_SUFFIXES) {
        if (lc.startsWith(suffix)) return suffix
    }
    return null
}

// ============================================================================
// DEFAULTS
// ============================================================================

const DEFAULTS = [
    {
        image: "https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=200&h=200&fit=crop",
        header: "Omnichannel Points",
        label: "Award points from every channel — online, offline, Marketplace",
    },
    {
        image: "https://images.unsplash.com/photo-1522071820081-009f0129c71c?w=200&h=200&fit=crop",
        header: "Tier & Privileges",
        label: "Set Tiers and privileges by membership level",
    },
    {
        image: "https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=200&h=200&fit=crop",
        header: "Rewards & Redemption",
        label: "Set up rewards, coupons, and perks for members to redeem with points",
    },
    {
        image: "https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?w=200&h=200&fit=crop",
        header: "Campaigns & Gamification",
        label: "Create campaigns — promotions, Missions, referrals, Double Points",
    },
    {
        image: "https://images.unsplash.com/photo-1472851294608-062f824d29cc?w=200&h=200&fit=crop",
        header: "Segment & Dashboard",
        label: "Segment customers, track behavior and campaign results in Dashboard",
    },
    {
        image: "https://images.unsplash.com/photo-1518186285589-2f7649de83e0?w=200&h=200&fit=crop",
        header: "AI Churn Prevention",
        label: "AI detects at-risk customers and sends personalized offers automatically",
    },
]

const PlaceholderIcon = () => (
    <svg width={57} height={59} viewBox="0 0 57 59" fill="none">
        <rect x="6" y="6" width="45" height="47" rx="8" stroke="#DDDDDD" strokeWidth="2" />
        <path d="M6 22h45M22 53V22" stroke="#DDDDDD" strokeWidth="2" />
    </svg>
)

// ============================================================================
// SINGLE CARD
// ============================================================================

interface CardProps {
    image: string | { src: string } | undefined
    header: string
    label: string
    tileBg: string
    tileBorderColor: string
    headerStyle: CSSProperties
    labelStyle: CSSProperties
}

function Card({ image, header, label, tileBg, tileBorderColor, headerStyle, labelStyle }: CardProps) {
    const src = resolveImageSrc(image)
    return (
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
            <div
                style={{
                    width: 144, height: 144, borderRadius: 32,
                    background: tileBg, border: `1px solid ${tileBorderColor}`,
                    boxShadow: "0px 4px 32px 0px rgba(0, 0, 0, 0.06)",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    flexShrink: 0, boxSizing: "border-box", overflow: "hidden",
                }}
            >
                {src ? (
                    <img src={src} alt={header} draggable={false}
                        style={{ width: "100%", height: "100%", objectFit: "contain" }} />
                ) : (
                    <PlaceholderIcon />
                )}
            </div>
            {header && <p style={{ margin: 0, maxWidth: 238, ...headerStyle }}>{header}</p>}
            <p style={{ margin: 0, marginTop: -4, maxWidth: 238, ...labelStyle }}>{label}</p>
        </div>
    )
}

// ============================================================================
// MAIN COMPONENT
// ============================================================================

/**
 * @framerDisableUnlink
 *
 * @framerIntrinsicWidth 1080
 * @framerIntrinsicHeight 600
 *
 * @framerSupportedLayoutWidth any-prefer-fixed
 * @framerSupportedLayoutHeight any
 */
export default function FeatureGrid(props: Props) {
    const {
        tileBg = "#FFFFFF",
        tileBorderColor = "#ECECEC",
        columnGap = 64,
        rowGap = 54,
        labelFont = {},
        labelFontSize = 16,
        labelColor = "#454140",
        headerFontSize = 24,
        headerColor = "#000000",
        style,
    } = props

    const { activeLocale } = useLocaleInfo()
    const localeKey = resolveLocaleKey(activeLocale?.code)

    const containerRef = useRef<HTMLDivElement>(null)
    const [columns, setColumns] = useState(3)

    useEffect(() => {
        const el = containerRef.current
        if (!el) return
        const observer = new ResizeObserver((entries) => {
            for (const entry of entries) {
                setColumns(entry.contentRect.width <= 720 ? 2 : 3)
            }
        })
        observer.observe(el)
        return () => observer.disconnect()
    }, [])

    const cards = [1, 2, 3, 4, 5, 6].map((n, i) => {
        const suffix = localeKey ? `_${localeKey}` : ""
        const imgKey = `image${n}${suffix}` as keyof Props
        const hdrKey = `header${n}${suffix}` as keyof Props
        const lblKey = `label${n}${suffix}` as keyof Props

        const imgDefault = `image${n}` as keyof Props
        const hdrDefault = `header${n}` as keyof Props
        const lblDefault = `label${n}` as keyof Props

        const image = (localeKey && resolveImageSrc(props[imgKey] as ImageProp))
            ? props[imgKey] as ImageProp
            : props[imgDefault] as ImageProp
        const header = (localeKey && props[hdrKey])
            ? (props[hdrKey] as string)
            : (props[hdrDefault] as string) || DEFAULTS[i].header
        const label = (localeKey && props[lblKey])
            ? (props[lblKey] as string)
            : (props[lblDefault] as string) || DEFAULTS[i].label

        return { image, header, label }
    })

    const labelStyle = resolveFontStyle(labelFont, labelFontSize, labelColor)
    const headerStyle: CSSProperties = {
        ...resolveFontStyle(labelFont, headerFontSize, headerColor),
        fontWeight: 800,
        lineHeight: 1.4,
    }

    return (
        <div ref={containerRef}
            style={{ ...style, width: "100%", background: "transparent", boxSizing: "border-box" }}>
            <div style={{
                display: "grid",
                gridTemplateColumns: `repeat(${columns}, 1fr)`,
                columnGap: columns === 2 ? 24 : columnGap,
                rowGap: columns === 2 ? 32 : rowGap,
                width: "100%",
            }}>
                {cards.map((card, i) => (
                    <Card key={i} image={card.image} header={card.header} label={card.label}
                        tileBg={tileBg} tileBorderColor={tileBorderColor}
                        headerStyle={headerStyle} labelStyle={labelStyle} />
                ))}
            </div>
        </div>
    )
}

// ============================================================================
// DEFAULT PROPS
// ============================================================================

FeatureGrid.defaultProps = {
    editLocale: "default",
    image1: DEFAULTS[0].image, header1: DEFAULTS[0].header, label1: DEFAULTS[0].label,
    image2: DEFAULTS[1].image, header2: DEFAULTS[1].header, label2: DEFAULTS[1].label,
    image3: DEFAULTS[2].image, header3: DEFAULTS[2].header, label3: DEFAULTS[2].label,
    image4: DEFAULTS[3].image, header4: DEFAULTS[3].header, label4: DEFAULTS[3].label,
    image5: DEFAULTS[4].image, header5: DEFAULTS[4].header, label5: DEFAULTS[4].label,
    image6: DEFAULTS[5].image, header6: DEFAULTS[5].header, label6: DEFAULTS[5].label,
    tileBg: "#FFFFFF",
    tileBorderColor: "#ECECEC",
    columnGap: 64,
    rowGap: 54,
    labelFont: {},
    labelFontSize: 16,
    labelColor: "#454140",
    headerFontSize: 24,
    headerColor: "#000000",
}

// ============================================================================
// PROPERTY CONTROLS
// ============================================================================

function cardControls(n: number, locale: string, localeLabel: string) {
    const suffix = locale === "default" ? "" : `_${locale}`
    const isDefault = locale === "default"
    const hidden = isDefault
        ? (props: any) => props.editLocale !== "default"
        : (props: any) => props.editLocale !== locale

    return {
        [`image${n}${suffix}`]: {
            type: ControlType.Image,
            title: `Card ${n} Image${isDefault ? "" : ` (${localeLabel})`}`,
            hidden,
        },
        [`header${n}${suffix}`]: {
            type: ControlType.String,
            title: `Card ${n} Header${isDefault ? "" : ` (${localeLabel})`}`,
            placeholder: isDefault ? `Feature ${n} title...` : `${localeLabel} title (blank = use default)`,
            hidden,
        },
        [`label${n}${suffix}`]: {
            type: ControlType.String,
            title: `Card ${n} Label${isDefault ? "" : ` (${localeLabel})`}`,
            placeholder: isDefault ? `Feature ${n} description...` : `${localeLabel} description (blank = use default)`,
            displayTextArea: true,
            hidden,
        },
    }
}

function allCardControls() {
    const locales = [
        { key: "default", label: "TH" },
        { key: "en", label: "EN" },
        { key: "zh", label: "ZH" },
        { key: "ja", label: "JA" },
    ]
    let controls: Record<string, any> = {}
    for (const { key, label } of locales) {
        for (let n = 1; n <= 6; n++) {
            controls = { ...controls, ...cardControls(n, key, label) }
        }
    }
    return controls
}

addPropertyControls(FeatureGrid, {
    editLocale: {
        type: ControlType.Enum,
        title: "Editing Locale",
        options: ["default", "en", "zh", "ja"],
        optionTitles: ["Thai (Default)", "English", "Chinese", "Japanese"],
        defaultValue: "default",
    },
    ...allCardControls(),
    tileBg: {
        type: ControlType.Color,
        title: "Tile Background",
        defaultValue: "#FFFFFF",
    },
    tileBorderColor: {
        type: ControlType.Color,
        title: "Tile Border",
        defaultValue: "#ECECEC",
    },
    columnGap: {
        type: ControlType.Number,
        title: "Column Gap",
        min: 0, max: 120, step: 4, defaultValue: 64, unit: "px", displayStepper: true,
    },
    rowGap: {
        type: ControlType.Number,
        title: "Row Gap",
        min: 0, max: 120, step: 4, defaultValue: 54, unit: "px", displayStepper: true,
    },
    labelFont: {
        type: ControlType.Font,
        title: "Label Font",
        controls: "extended",
        displayFontSize: false,
        displayTextAlignment: true,
        defaultFontType: "sans-serif",
    },
    headerFontSize: {
        type: ControlType.Number,
        title: "Header Size",
        min: 14, max: 48, step: 1, defaultValue: 24, unit: "px", displayStepper: true,
    },
    headerColor: {
        type: ControlType.Color,
        title: "Header Color",
        defaultValue: "#000000",
    },
    labelFontSize: {
        type: ControlType.Number,
        title: "Label Size",
        min: 10, max: 40, step: 1, defaultValue: 16, unit: "px", displayStepper: true,
    },
    labelColor: {
        type: ControlType.Color,
        title: "Label Color",
        defaultValue: "#454140",
    },
})
