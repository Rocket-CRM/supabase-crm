/**
 * Executive overview pillar matrix — Current state → Future state → Impact.
 * Pattern mirrors Rocket Deck `PillarMatrix` (internal-proposal rocket-graphics).
 *
 * Authoring source for general-proposal runs. Viewer renders `index.html` from
 * `data.en.json` / `data.th.json`. Embed in markdown via `{{diagram:executive-overview}}`.
 */
import { Fragment } from "react";

export type Pillar = {
  objective: string;
  current: string[];
  future: string[];
  impact: string[];
};

export type PillarMatrixData = {
  kind: "pillar_matrix";
  title?: string;
  pillars: Pillar[];
};

type Props = {
  data: PillarMatrixData;
  /** Optional className for host layouts */
  className?: string;
};

function BulletCell({ items }: { items: string[] }) {
  return (
    <ul className="pillar-bullets">
      {items.map((item, idx) => (
        <li key={idx}>
          <span className="pillar-dot" aria-hidden />
          <span>{item}</span>
        </li>
      ))}
    </ul>
  );
}

function HeaderCell({
  children,
  variant,
}: {
  children: React.ReactNode;
  variant: "primary" | "secondary";
}) {
  return (
    <div className={`pillar-head pillar-head--${variant}`}>{children}</div>
  );
}

export function PillarMatrix({ data, className }: Props) {
  return (
    <figure
      className={["proposal-pillar-matrix", className].filter(Boolean).join(" ")}
      data-diagram="executive-overview"
    >
      {data.title ? (
        <figcaption className="pillar-caption">{data.title}</figcaption>
      ) : null}
      <div className="pillar-scroll">
        <div className="pillar-grid">
          <HeaderCell variant="primary">Objectives</HeaderCell>
          <HeaderCell variant="primary">Current state</HeaderCell>
          <div aria-hidden className="pillar-spacer" />
          <HeaderCell variant="primary">Future state</HeaderCell>
          <HeaderCell variant="secondary">Impact</HeaderCell>

          {data.pillars.map((pillar, idx) => (
            <Fragment key={`${pillar.objective}-${idx}`}>
              <div className={`pillar-objective tint-${idx % 3}`}>
                {pillar.objective}
              </div>
              <div className="pillar-cell">
                <BulletCell items={pillar.current} />
              </div>
              <div className="pillar-arrow" aria-hidden>
                →
              </div>
              <div className="pillar-cell">
                <BulletCell items={pillar.future} />
              </div>
              <div className={`pillar-cell pillar-impact tint-${idx % 3}`}>
                <BulletCell items={pillar.impact} />
              </div>
            </Fragment>
          ))}
        </div>
      </div>
    </figure>
  );
}

export default PillarMatrix;
