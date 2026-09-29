# ReproducibleSDOH

> **Status: planning / under construction.** Nothing here is ready to use yet.

ReproducibleSDOH will be the umbrella R package for the **ReproducibleX** family of neighborhood socioeconomic indices built from the US Census Bureau's American Community Survey:

| Package | Indices |
|---|---|
| [ReproducibleYostIndex](https://github.com/HanLabCollaboration/ReproducibleYostIndex) | Yost Index |
| [ReproducibleNDI](https://github.com/HanLabCollaboration/ReproducibleNDI) | Neighborhood Deprivation Index (Messer, Powell-Wiley), Index of Concentration at the Extremes (ICE) |
| [ReproducibleSDI](https://github.com/HanLabCollaboration/ReproducibleSDI) | Social Deprivation Index |
| [ReproducibleCDI](https://github.com/HanLabCollaboration/ReproducibleCDI) | Community Deprivation Index |

It will offer two ways to get an index:

- **`get*()` functions** (`getYost()`, `getNDI()`, `getICE()`, `getSDI()`, `getCDI()`) that download **pre-computed** indices, without a Census API key. The files are Parquet, published as releases of `ReproducibleSDOH-data`.
- **`computeSDOH()`**, which hands off to the sibling packages to compute an index locally with any options.

This repository also holds the **Stanford Sherlock (SLURM) pipeline** that pre-computes every index × geography × scope × year. It lives in `pipeline/` and is not part of the installed package.

## Plans

- [`plan/plan.md`](plan/plan.md): the shared design: repositories, data format, package API, pipeline, release workflow.
- [`plan/plan_NDI.md`](plan/plan_NDI.md): the NDI family (Messer, Powell-Wiley, ICE), the first family through the pipeline.

## License

MIT © Rafael Catoia Pulgrossi, Tae Yoon Lee
