/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{js,ts,jsx,tsx,mdx}",
    "./index.html",
  ],
  theme: {
    extend: {
      colors: {
        primary: "var(--primary)",
        "primary-hover": "var(--primary-hover)",
        "primary-active": "var(--primary-active)",
        "primary-light": "var(--primary-light)",
        background: "var(--background)",
        foreground: "var(--foreground)",
        border: "var(--border)",
        "card-bg": "var(--card-bg)",
      },
      fontFamily: {
        sans: ["var(--font-inter)", "Arial", "Helvetica", "sans-serif"],
        "abc-favorit": ["var(--font-abc-favorit)", "Arial", "Helvetica", "sans-serif"],
      },
      borderRadius: {
        sm: "var(--radius-sm)",
        md: "var(--radius-md)",
        lg: "var(--radius-lg)",
        xl: "var(--radius-xl)",
      },
    },
  },
  plugins: [],
};

