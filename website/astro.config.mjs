import starlight from "@astrojs/starlight";
import a11yEmoji from "@fec/remark-a11y-emoji";
import { defineConfig } from "astro/config";
import starlightLinksValidator from "starlight-links-validator";
import starlightLlmsTxt from "starlight-llms-txt";

// https://astro.build/config
export default defineConfig({
	site: "https://slate.tylerbutler.com",
	prefetch: {
		defaultStrategy: "hover",
		prefetchAll: true,
	},
	integrations: [
		starlight({
			title: "slate",
			editLink: {
				baseUrl:
					"https://github.com/tylerbutler/slate/edit/main/website/",
			},
			description:
				"Type-safe Gleam wrapper for Erlang DETS (Disk Erlang Term Storage).",
			lastUpdated: true,
			logo: {
				src: "./src/assets/slate-wordmark.webp",
				alt: "",
				replacesTitle: true,
				width: 423,
				height: 132,
			},
			favicon: "/favicon.png",
			customCss: [
				"@fontsource/schibsted-grotesk/400.css",
				"@fontsource/schibsted-grotesk/600.css",
				"@fontsource/schibsted-grotesk/700.css",
				"@fontsource/spline-sans-mono/400.css",
				"@fontsource/spline-sans-mono/600.css",
				"./src/styles/fonts.css",
				"./src/styles/custom.css",
			],
			plugins: [
				starlightLlmsTxt(),
				starlightLinksValidator(),
			],
			components: {
				Head: "./src/components/Head.astro",
			},
			social: [
				{
					icon: "github",
					label: "GitHub",
					href: "https://github.com/tylerbutler/slate",
				},
			],
			sidebar: [
				{
					label: "Start Here",
					items: [
						{
							label: "What is slate?",
							slug: "introduction",
						},
						{
							label: "Installation",
							slug: "installation",
						},
						{
							label: "Quick Start",
							slug: "quick-start",
						},
					],
				},
				{
					label: "Guides",
					items: [
						{
							label: "Set Tables",
							slug: "guides/set-tables",
						},
						{
							label: "Bag Tables",
							slug: "guides/bag-tables",
						},
						{
							label: "Duplicate Bag Tables",
							slug: "guides/duplicate-bag-tables",
						},
					],
				},
				{
					label: "Operations",
					items: [
						{
							label: "Safe Resource Management",
							slug: "advanced/with-table",
						},
						{
							label: "Error Handling",
							slug: "advanced/error-handling",
						},
						{
							label: "Troubleshooting",
							slug: "advanced/troubleshooting",
						},
					],
				},
				{
					label: "Reference",
					items: [
						{
							label: "Limitations",
							slug: "advanced/limitations",
						},
						{
							label: "Stability & Versioning",
							slug: "advanced/stability",
						},
					],
				},
			],
		}),
	],
	markdown: {
		smartypants: false,
		remarkPlugins: [
			a11yEmoji,
		],
	},
});
