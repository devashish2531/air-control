import { Reveal } from "@/components/Reveal";
import { asset } from "@/lib/urls";

/**
 * Hero spec, "HeroDevice": a pure CSS/SVG mock of an iPhone (running the Air
 * Control touchpad) sitting in front of a Mac window, with a finger dot and a
 * macOS arrow cursor looping the same L-shaped path (cursor travel scaled
 * ×1.6) to show the app moving the pointer. No screenshots, no JS — layout,
 * proportions and motion all live in hero.css.
 *
 * The whole illustration is decorative (aria-hidden); the visually-hidden
 * paragraph below it is the accessible description.
 */
export function HeroDevice() {
  return (
    <Reveal as="div" className="hero__device" delay={400}>
      <div className="device" aria-hidden="true">
        <div className="mac">
          <div className="mac__bar">
            <span className="mac__dot mac__dot--red" />
            <span className="mac__dot mac__dot--yellow" />
            <span className="mac__dot mac__dot--green" />
            <span className="mac__bar-spacer" />
            <img
              className="mac__bar-icon"
              src={asset("/icon-mac-64.png")}
              alt=""
              width={16}
              height={16}
              decoding="async"
            />
          </div>

          <div className="mac__body">
            <span className="mac__block mac__block--a" />
            <span className="mac__block mac__block--b" />
            <span className="mac__button">
              <span className="mac__button-accent" />
            </span>
          </div>

          <svg
            className="cursor"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            focusable="false"
          >
            <path
              d="M4 2 L4 19.5 L8.2 16 L11 21.8 L13.6 20.5 L10.9 15 L16.5 15 Z"
              fill="#000"
              stroke="#fff"
              strokeWidth="1.3"
              strokeLinejoin="round"
            />
          </svg>
        </div>

        <div className="phone">
          <div className="phone__screen">
            <div className="phone__inset">
              <div className="phone__island" />
            </div>

            <div className="phone__titlebar">
              <img
                className="phone__app-icon"
                src={asset("/icon-ios-64.png")}
                alt=""
                width={28}
                height={28}
                decoding="async"
              />
              <span className="phone__app-name">Air Control</span>
            </div>

            <div className="phone__tabs">
              <span className="phone__tab phone__tab--active">
                <span className="phone__tab-label">Pad</span>
              </span>
              <span className="phone__tab">
                <span className="phone__tab-label">Air</span>
              </span>
              <span className="phone__tab">
                <span className="phone__tab-label">Keys</span>
              </span>
              <span className="phone__tab">
                <span className="phone__tab-label">Remote</span>
              </span>
            </div>

            <div className="phone__touchpad">
              <span className="finger" />
            </div>
          </div>
        </div>
      </div>

      <p className="visually-hidden">
        Illustration: an iPhone showing the Air Control touchpad moving the
        cursor on a Mac.
      </p>
    </Reveal>
  );
}
