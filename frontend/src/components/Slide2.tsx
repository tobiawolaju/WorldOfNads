import React, { useEffect, useMemo, useState } from "react";
import "./Slide2.css";

type LogoItem = {
  id: string;
  imageUrl: string;
  alt: string;
};

const fallbackLogos: LogoItem[] = [
  { id: "logo-1", imageUrl: "/logo.png", alt: "Brand logo 1" },
  { id: "logo-2", imageUrl: "/logo.png", alt: "Brand logo 2" },
  { id: "logo-3", imageUrl: "/logo.png", alt: "Brand logo 3" },
  { id: "logo-4", imageUrl: "/logo.png", alt: "Brand logo 4" },
  { id: "logo-5", imageUrl: "/logo.png", alt: "Brand logo 5" },
  { id: "logo-6", imageUrl: "/logo.png", alt: "Brand logo 6" },
  { id: "logo-7", imageUrl: "/logo.png", alt: "Brand logo 7" },
  { id: "logo-8", imageUrl: "/logo.png", alt: "Brand logo 8" },
  { id: "logo-9", imageUrl: "/logo.png", alt: "Brand logo 9" }
];

const chunkIntoColumns = (items: LogoItem[], columns: number): LogoItem[][] => {
  const result: LogoItem[][] = Array.from({ length: columns }, () => []);

  items.forEach((item, index) => {
    result[index % columns].push(item);
  });

  return result;
};

const Slide2: React.FC = () => {
  const [logos, setLogos] = useState<LogoItem[]>(fallbackLogos);

  useEffect(() => {
    let active = true;

    const loadLogos = async () => {
      try {
        const response = await fetch("/slide2-logos.json");

        if (!response.ok) {
          return;
        }

        const data: LogoItem[] = await response.json();

        if (active && Array.isArray(data) && data.length > 0) {
          setLogos(data);
        }
      } catch {
        // Keep fallback logos if JSON loading fails.
      }
    };

    loadLogos();

    return () => {
      active = false;
    };
  }, []);

  const columnData = useMemo(() => chunkIntoColumns(logos, 3), [logos]);

  return (
    <section className="slide2" aria-label="Scrolling logo wall">
      <div className="slide2-grid">
        {columnData.map((columnItems, index) => (
          <div key={`column-${index}`} className="slide2-column">
            <div
              className={`slide2-column-track slide2-speed-${index + 1}`}
              aria-hidden="true"
            >
              {[...columnItems, ...columnItems].map((item, itemIndex) => (
                <img
                  key={`${item.id}-${itemIndex}`}
                  src={item.imageUrl}
                  alt={item.alt}
                  className="slide2-logo"
                  loading="lazy"
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
};

export default Slide2;
