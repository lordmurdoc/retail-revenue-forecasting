-- ============================================================================
-- Retail Revenue Forecasting | PostgreSQL database setup
-- ============================================================================
-- Source: synthetic daily coffee sales, 2024-01-01 through 2025-12-31.
-- Original CSV: demanda_cafe_diaria_2024_2025.csv
-- Database: coofee_sales  (name kept as used in the original project)
-- Table: public.demanda_dia
--
-- Run this file WITH psql, from the repository root (next to the CSV):
--
--   psql -h localhost -U postgres -d postgres -f setup_database.sql
--
-- Replace 'postgres' with your database role if needed. The role must be
-- allowed to create a database if 'coofee_sales' does not already exist.
-- This file includes psql commands (\connect, \copy, \gexec); it is not
-- intended to run unchanged in a generic SQL editor or via SQLAlchemy.
-- ============================================================================

-- Stop immediately if any SQL statement or psql command fails.
\set ON_ERROR_STOP on

-- 1. Create the database, only if it does not already exist.
--    PostgreSQL does not support CREATE DATABASE IF NOT EXISTS.
SELECT format('CREATE DATABASE %I', 'coofee_sales')
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_database
    WHERE datname = 'coofee_sales'
)
\gexec

-- 2. Connect to the project database.
\connect coofee_sales

BEGIN;

-- 3. Define the daily sales table.
--    One product may appear at most once per date (composite primary key).
--    NUMERIC is preferred to floating-point types for monetary amounts.
CREATE TABLE IF NOT EXISTS public.demanda_dia (
    data                DATE           NOT NULL,
    produto             VARCHAR(30)    NOT NULL,
    preco_unitario      NUMERIC(10, 2) NOT NULL CHECK (preco_unitario >= 0),
    promocao            SMALLINT       NOT NULL CHECK (promocao IN (0, 1)),
    desconto_percentual INTEGER        NOT NULL CHECK (desconto_percentual BETWEEN 0 AND 100),
    feriado_indicador   SMALLINT       NOT NULL CHECK (feriado_indicador IN (0, 1)),
    unidades_vendidas   INTEGER        NOT NULL CHECK (unidades_vendidas >= 0),
    CONSTRAINT pk_demanda_dia PRIMARY KEY (data, produto)
);

-- 4. Load the CSV through a temporary staging table.
--    This allows the setup to be rerun without inserting duplicate rows.
--    Existing rows are preserved when (data, produto) already exists.
CREATE TEMP TABLE demanda_dia_import (
    LIKE public.demanda_dia
) ON COMMIT DROP;

-- \copy reads the CSV from the local machine running psql.
-- This relative path assumes psql was launched from the repository root.
\copy demanda_dia_import (data, produto, preco_unitario, promocao, desconto_percentual, feriado_indicador, unidades_vendidas) FROM 'demanda_cafe_diaria_2024_2025.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF8')

INSERT INTO public.demanda_dia (
    data,
    produto,
    preco_unitario,
    promocao,
    desconto_percentual,
    feriado_indicador,
    unidades_vendidas
)
SELECT
    data,
    produto,
    preco_unitario,
    promocao,
    desconto_percentual,
    feriado_indicador,
    unidades_vendidas
FROM demanda_dia_import
WHERE TRUE  -- Avoid INSERT ... SELECT / ON CONFLICT parsing ambiguity.
ON CONFLICT (data, produto) DO NOTHING;

COMMIT;

-- 5. Validate the imported dataset.
--    Expected for a fresh import: 731 rows, 2024-01-01 to 2025-12-31.
SELECT
    COUNT(*)                  AS total_records,
    COUNT(DISTINCT data)      AS distinct_days,
    COUNT(DISTINCT produto)   AS distinct_products,
    MIN(data)                 AS first_date,
    MAX(data)                 AS last_date
FROM public.demanda_dia;

-- Basic aggregate for a quick sanity check.
-- Revenue is derived in Python and is not stored as a source CSV column.
SELECT
    SUM(unidades_vendidas)                          AS total_units_sold,
    ROUND(AVG(unidades_vendidas), 2)                 AS average_daily_units,
    ROUND(SUM(preco_unitario * unidades_vendidas), 2) AS total_revenue_brl
FROM public.demanda_dia;

-- Note: CREATE TABLE IF NOT EXISTS does not modify an existing table schema.
-- If you created an incompatible version previously, migrate it separately.
