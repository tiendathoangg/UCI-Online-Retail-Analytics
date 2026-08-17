# Online Retail Sales Analytics

## About This Project

This project started with a simple goal: **to understand what working with real-world transaction data actually looks like.**

I used the **UCI Online Retail dataset**, containing transactions from a UK-based online retailer. Unlike the clean datasets often used in coursework, I found missing customer IDs, duplicated records, cancellations, negative quantities, and transactions that could not simply be treated as normal sales.

Instead of jumping straight into visualisations, I wanted to understand these problems first and build the analysis step by step.

## What I Tried to Solve

I built a small data pipeline using **Python and MySQL** to:

1. explore and identify data-quality problems;
2. clean and classify transactions without blindly removing unusual records;
3. create consistent measures such as completed and net revenue;
4. organise the data into a Star Schema; and
5. use the final dataset to explore sales, products, countries, cancellations, and customers.

I imagined the main stakeholder as a **Sales or Operations Manager** who wants to understand business performance without having to interpret raw transaction records.

## What I Learned — and What Comes Next

The biggest lesson from this project was that **getting an answer from data is often easier than deciding whether that answer can be trusted.**

The current pipeline provides a useful foundation for sales analysis, but there is still much more to explore. Missing customer IDs limit customer-level analysis, cancellation data does not explain *why* orders were cancelled, and the dataset covers only around one year.

These limitations also create opportunities for the next stage of the project, particularly **customer behaviour, RFM segmentation, product relationships, and deeper cancellation analysis**.
