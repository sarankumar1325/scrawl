import React from "react";

export function ScrawlLogo() {
  return (
    <div className="scrawl-logo" aria-label="Scrawl">
      <svg
        viewBox="112 76 288 376"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        className="scrawl-logo-icon"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="44"
      >
        <path d="M374 148 C332 92 212 92 174 154 C140 212 200 248 264 264 C334 282 374 318 342 374" stroke="currentColor" />
        <path d="M342 374 C306 432 190 428 138 366" stroke="#ff5a5f" />
      </svg>
      <span className="scrawl-logo-text">Scrawl</span>
    </div>
  );
}
