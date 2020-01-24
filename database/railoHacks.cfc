/************************************************************
*
*	Copyright (c) 2007-2015, Abram Adams
*
*	Licensed under the Apache License, Version 2.0 (the "License");
*	you may not use this file except in compliance with the License.
*	You may obtain a copy of the License at
*
*		http://www.apache.org/licenses/LICENSE-2.0
*
*	Unless required by applicable law or agreed to in writing, software
*	distributed under the License is distributed on an "AS IS" BASIS,
*	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
*	See the License for the specific language governing permissions and
*	limitations under the License.
*
************************************************************
*
*		Component	: railoHacks.cfc
*		Author		: Abram Adams
*		Date		: 9/10/2015
*		@version 0.0.02
*		@updated 9/10/2015
*		Description	: Helper methods to overcome compatibility
*		issues between Railo/Lucee and Adobe ColdFusion
*
*		Update		: 2019-09-26
*		By		: -A
*		Description	: Added caching, this is an instance object rather than a static global.
*					There are several of these SQL round-trips made in a single request.
*					This is an attempt to reduce, times can be upwards of 100ms.
*
***********************************************************/
component accessors="true" {
	property string dsn;
	public function init( required string dsn ){
		setDsn( dsn );
	}

	public any function getDBVersion( string datasource = this.getDsn() ){
		var d = "";
		dbinfo datasource=datasource name="d" type="version";

		return d;
	}

	public any function getDBName( string datasource = this.getDsn() ){
		var tables = "";
		dbinfo datasource=datasource name="tables" type="tables";
		return tables.table_cat[1];
	}

	public any function getColumns( required string table, string datasource = this.getDsn() )
	{
		var columns = GetCachedColumns( table, datasource );

		if ( IsNull( columns ) )
		{
			var columns = "";
			dbinfo datasource=datasource name="columns" type="columns" table="#table#";

			SetCachedColumns( table, datasource, columns );
		}

		return columns;
	}


	public any function getTables( string datasource = this.getDsn(), string pattern = "" )
	{
		var tables = GetCachedTables( datasource, pattern );
		if ( IsNull( tables ) )
		{
			dbinfo datasource=datasource name="tables" type="tables" table=pattern pattern=pattern;

			if ( tables.recordCount )
				SetCachedTables( datasource, pattern, tables );
			else
			{
				/*
				* Filtering tables by pattern is case sensitive, though the source of pattern could have
				* 	come from extracting metadata from an object, which does not retain case.
				* This could also be something requesting table schemata info for a column, which seems foolish at best.
				* Either case, pull all from cache or fetch, then filter.
				*/
				var allTables = GetCachedTables( datasource, "all" );
				if ( IsNull( allTables ) )
				{
					// Get them all and cache
					dbinfo datasource=datasource name="allTables" type="tables";

					SetCachedTables( datasource, "all", allTables );

					// If the result is empty, the calling function passed in a column name in the pattern string.
					// We'll still cache it.
				}

				tables = QueryExecute(
					"SELECT * FROM allTables WHERE table_name = :tablePattern",
					{ tablePattern: pattern },
					{ dbtype: 'query' }
				);

				if ( tables.recordcount )
					SetCachedTables( datasource, pattern, tables );

			}
		}

		return tables;
	}


	/**
	* Returns a query containing the table index info for the provided table name.
	* @table the name of the table for which we need index information.
	**/
	public any function getIndex( required string table, string datasource = this.getDsn() )
	{
		var index = GetCachedIndex( table, datasource );
		if ( IsNull( index ) )
		{
			dbinfo datasource=datasource name="index" type="index" table="#table#";
			SetCachedIndex( table, datasource, index );
		}

		return index;
	}



	/**
	* Handles fetching of a cached db info query containing column definitions for the provided table.
	* @table the name of the table for which we need column definitions.
	* @datasource the name of the DSN, used here only for the cache key.
	**/
	private any function GetCachedColumns( required string table, required string datasource )
	{
		var cacheKey = "railoHacks/columns/#table#/#datasource#";

		// CacheDelete( cacheKey );	// Debug purposes
		/*
		try {
			throw();
		}
		catch( ex )
		{
			var stack = ex.tagcontext.reduce( (p,c) => {
				p.append( c.Raw_Trace );
				return p;
			}, [] );
			WriteDump( var={ "#cacheKey#": stack, "cache-item": CacheGet( cacheKey ) }, label=getFunctionCalledName(), showUDFs=false, abort=false );
		}
		*/
		return Duplicate( CacheGet( cacheKey ) );
	}

	/**
	* Handles caching of the query column definitions for the provided table.
	* @table the name of the table for which we need column definitions.
	* @datasource the name of the DSN, used here only for the cache key.
	* @columns the query containing the result from the dbinfo lookup.
	**/
	private void function SetCachedColumns( required string table, required string datasource, required query columns )
	{
		var cacheKey = "railoHacks/columns/#table#/#datasource#";

		CachePut( cacheKey, Duplicate( columns ) );
	}


	/**
	* Handles fetching of a cached db info query containing table definitions for the provided table name pattern.
	* @pattern the name of the table for which we need column definitions.
	* @datasource the name of the DSN, used here only for the cache key.
	**/
	private any function GetCachedTables( required string datasource, required string pattern )
	{
		if ( !Len(pattern) )
			pattern = "all";

		var cacheKey = "railoHacks/tables/#pattern#/#datasource#";

		// CacheDelete( cacheKey );	// Debug purposes

		return Duplicate( CacheGet(cacheKey) );
	}


	/**
	* Handles caching of the query containing table definitions for the provided pattern.
	* @datasource the name of the DSN, used here only for the cache key.
	* @pattern the name of the table or pattern for which we need table definitions.
	* @tables the query containing the result from the dbinfo lookup.
	**/
	private void function SetCachedTables( required string datasource, required string pattern, required query tables )
	{
		if ( !Len(pattern) )
			pattern = "all";

		var cacheKey = "railoHacks/tables/#pattern#/#datasource#";

		CachePut( cacheKey, Duplicate( tables ) );
	}


	/**
	* Handles fetching of a cached db info query containing index definitions for the provided table.
	* @table the name of the table for which we need index definitions.
	* @datasource the name of the DSN, used here only for the cache key.
	**/
	private any function GetCachedIndex( required string table, required string datasource )
	{
		var cacheKey = "railoHacks/indices/#table#/#datasource#";

		// CacheDelete( cacheKey );	// Debug purposes

		return Duplicate( CacheGet(cacheKey) );
	}


	/**
	* Handles caching of the query containing index definitions for the provided table.
	* @table the name of the table for which we need index definitions.
	* @datasource the name of the DSN, used here only for the cache key.
	* @index the query containing the result from the dbinfo lookup.
	**/
	private void function SetCachedIndex( required string table, required string datasource, required query index )
	{
		var cacheKey = "railoHacks/indices/#table#/#datasource#";

		CachePut( cacheKey, Duplicate( index ) );
	}

}
