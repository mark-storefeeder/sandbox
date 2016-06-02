/****** Object:  StoredProcedure [dbo].[OrderImport_Process]    Script Date: 01/06/2016 12:49:25 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[OrderImport_Process]
	@OrderImportID INT,
	@ChannelID INT,
	@LoggedUserID INT,
	@SuccessCount INT OUTPUT,
	@ErrorCount INT OUTPUT
AS
BEGIN
	DECLARE @X INT
	SET NOCOUNT ON
	SET @SuccessCount = 0
	SET @ErrorCount = 0
	DECLARE @AccountID INT = (SELECT TOP 1 AccountID FROM Channel WHERE ChannelID = @ChannelID)
	DECLARE @SpreadsheetRowIndex INT
	DECLARE @OrderReference NVARCHAR(MAX)
	DECLARE @OrderSpecialInstructions NVARCHAR(500)
	DECLARE @OrderDate DATETIME2(7)
	DECLARE @OrderWeightKG DECIMAL(19, 4)
	DECLARE @OrderSubtotal MONEY
	DECLARE @OrderShippingCost MONEY
	DECLARE @OrderTotal MONEY
	DECLARE @OrderPackagingID INT
	DECLARE @ShippingCustomerTitle NVARCHAR(10)
	DECLARE @ShippingCustomerFirstName NVARCHAR(100)
	DECLARE @ShippingCustomerLastName NVARCHAR(100)
	DECLARE @ShippingCustomerPhone varchar(25)
	DECLARE @ShippingCustomerEmail NVARCHAR(100)
	DECLARE @ShippingAddressCompanyName NVARCHAR(100)
	DECLARE @ShippingAddressLine1 NVARCHAR(100)
	DECLARE @ShippingAddressLine2 NVARCHAR(100)
	DECLARE @ShippingAddressLine3 NVARCHAR(100)
	DECLARE @ShippingAddressCity NVARCHAR(100)
	DECLARE @ShippingAddressCounty NVARCHAR(100)
	DECLARE @ShippingAddressPostcode NVARCHAR(20)
	DECLARE @ShippingAddressCountry NVARCHAR(200)
	DECLARE @BillingAddressCompanyName NVARCHAR(100)
	DECLARE @BillingAddressLine1 NVARCHAR(100)
	DECLARE @BillingAddressLine2 NVARCHAR(100)
	DECLARE @BillingAddressLine3 NVARCHAR(100)
	DECLARE @BillingAddressCity NVARCHAR(100)
	DECLARE @BillingAddressCounty NVARCHAR(100)
	DECLARE @BillingAddressPostcode NVARCHAR(20)
	DECLARE @BillingAddressCountry NVARCHAR(200)
	DECLARE @ProductSKU NVARCHAR(100)
	DECLARE @ProductName NVARCHAR(800)
	DECLARE @ProductUnitPrice MONEY
	DECLARE @ProductUnitWeightKG DECIMAL(19, 4)
	DECLARE @ProductQuantity INT
	DECLARE @CountryMappings TABLE
	(
		CountryID int,
		CountryNameOrCode NVARCHAR(200)
	)
	-- Improve performance by building a list of countries we'll need for mapping in advance:
	INSERT INTO @CountryMappings
	(
		CountryID,
		CountryNameOrCode
	)
	SELECT
		80, -- United Kingdom
		''
	UNION
	SELECT DISTINCT
		COALESCE(
			(SELECT TOP 1 CountryID FROM Country WHERE Name = CountryNameOrCode OR DisplayName = CountryNameOrCode OR TwoLetterISOCode = CountryNameOrCode OR ThreeLetterISOCode = CountryNameOrCode),
			(SELECT TOP 1 CountryID FROM CountryMapping WHERE CountryName = CountryNameOrCode)),
		CountryNameOrCode
	FROM
		(
			SELECT DISTINCT CountryNameOrCode = LTRIM(RTRIM(ShippingAddressCountry)) FROM OrderImportItem WHERE OrderImportID = @OrderImportID AND ShippingAddressCountry IS NOT NULL
			UNION SELECT DISTINCT CountryNameOrCode = LTRIM(RTRIM(BillingAddressCountry)) FROM OrderImportItem WHERE OrderImportID = @OrderImportID AND BillingAddressCountry IS NOT NULL
		) AS c
	WHERE
		CountryNameOrCode != ''
	DECLARE OrderImportItemCursor CURSOR FOR  
		SELECT
			SpreadsheetRowIndex,
			LTRIM(RTRIM(OrderReference)),
			LTRIM(RTRIM(OrderSpecialInstructions)),
			ISNULL(OrderDate, GETUTCDATE()),
			OrderWeightKG,
			OrderSubtotal,
			OrderShippingCost,
			OrderTotal,
			OrderPackagingID,
			LTRIM(RTRIM(ShippingCustomerTitle)),
			LTRIM(RTRIM(ShippingCustomerFirstName)),
			LTRIM(RTRIM(ShippingCustomerLastName)),
			LTRIM(RTRIM(ShippingCustomerPhone)),
			LTRIM(RTRIM(ShippingCustomerEmail)),
			LTRIM(RTRIM(ShippingAddressCompanyName)),
			LTRIM(RTRIM(ShippingAddressLine1)),
			LTRIM(RTRIM(ShippingAddressLine2)),
			LTRIM(RTRIM(ShippingAddressLine3)),
			LTRIM(RTRIM(ShippingAddressCity)),
			LTRIM(RTRIM(ShippingAddressCounty)),
			LTRIM(RTRIM(ShippingAddressPostcode)),
			ISNULL(LTRIM(RTRIM(ShippingAddressCountry)), ''),
			LTRIM(RTRIM(BillingAddressCompanyName)),
			LTRIM(RTRIM(BillingAddressLine1)),
			LTRIM(RTRIM(BillingAddressLine2)),
			LTRIM(RTRIM(BillingAddressLine3)),
			LTRIM(RTRIM(BillingAddressCity)),
			LTRIM(RTRIM(BillingAddressCounty)),
			LTRIM(RTRIM(BillingAddressPostcode)),
			ISNULL(LTRIM(RTRIM(BillingAddressCountry)), ''),
			LTRIM(RTRIM(ProductSKU)),
			LTRIM(RTRIM(ProductName)),
			ProductUnitPrice,
			ProductUnitWeightKG,
			ProductQuantity
		FROM
			OrderImportItem
		WHERE
			OrderImportID = @OrderImportID
			-- Group by OrderReference so that only the first row with each OrderReference will be imported, and subsequent rows will just be used for product information:
			AND SpreadsheetRowIndex IN
			(
				SELECT
					SpreadsheetRowIndex
				FROM
				(
					SELECT
						SpreadsheetRowIndex,
						OrderReference = LTRIM(RTRIM(OrderReference)),
						RowNumberPartitionedByOrderReference = ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(OrderReference)) ORDER BY SpreadsheetRowIndex)
					FROM
						OrderImportItem
					WHERE
						OrderImportID = @OrderImportID
				) AS a
				WHERE
					OrderReference IS NULL
					OR OrderReference = ''
					OR RowNumberPartitionedByOrderReference = 1
			)
        ORDER BY
            SpreadsheetRowIndex
	OPEN OrderImportItemCursor
	FETCH NEXT FROM OrderImportItemCursor INTO
		@SpreadsheetRowIndex,
		@OrderReference,
		@OrderSpecialInstructions,
		@OrderDate,
		@OrderWeightKG,
		@OrderSubtotal,
		@OrderShippingCost,
		@OrderTotal,
		@OrderPackagingID,
		@ShippingCustomerTitle,
		@ShippingCustomerFirstName,
		@ShippingCustomerLastName,
		@ShippingCustomerPhone,
		@ShippingCustomerEmail,
		@ShippingAddressCompanyName,
		@ShippingAddressLine1,
		@ShippingAddressLine2,
		@ShippingAddressLine3,
		@ShippingAddressCity,
		@ShippingAddressCounty,
		@ShippingAddressPostcode,
		@ShippingAddressCountry,
		@BillingAddressCompanyName,
		@BillingAddressLine1,
		@BillingAddressLine2,
		@BillingAddressLine3,
		@BillingAddressCity,
		@BillingAddressCounty,
		@BillingAddressPostcode,
		@BillingAddressCountry,
		@ProductSKU,
		@ProductName,
		@ProductUnitPrice,
		@ProductUnitWeightKG,
		@ProductQuantity
	WHILE @@FETCH_STATUS = 0  
	BEGIN
		DECLARE @ErrorType INT = NULL
		DECLARE @ErrorMessage NVARCHAR(MAX) = NULL
		DECLARE @ErrorMessageParameters NVARCHAR(255) = NULL
		BEGIN TRAN
		BEGIN TRY
			DECLARE @ShippingAddressCountryID INT = (SELECT CountryID FROM @CountryMappings WHERE CountryNameOrCode = @ShippingAddressCountry)
			IF @ShippingAddressCountryID IS NULL
			BEGIN
				SET @ErrorType = 8 -- NoCountryFound
				SET @ErrorMessage = 'Country ''' + @ShippingAddressCountry + ''' could not be found'
				SET @ErrorMessageParameters = '{"country":"' + REPLACE(REPLACE(@ShippingAddressCountry, '\', '\\'), '"', '\"') + '"}'
				GOTO _ROLLBACK
			END
			IF (@ShippingAddressCountryID = 80 OR @ShippingAddressCountryID = 17144 OR @ShippingAddressCountryID = 17145) AND @ShippingAddressPostcode IS NULL -- United Kingdom, Guernsey and Jersey addresses require postcode
			OR (@ShippingAddressCountryID = 80 OR @ShippingAddressCountryID = 17144 OR @ShippingAddressCountryID = 17145) AND @ShippingAddressPostcode = ''
			BEGIN
				SET @ErrorType = 13 -- NoUkShippingAddressPostcode
				SET @ErrorMessage = 'Postcode is required for UK orders'
				GOTO _ROLLBACK
			END
			DECLARE @BillingAddressCountryID INT = (SELECT CountryID FROM @CountryMappings WHERE CountryNameOrCode = @BillingAddressCountry)
			IF @BillingAddressCountryID IS NULL
			BEGIN
				SET @ErrorType = 8 -- NoCountryFound
				SET @ErrorMessage = 'Country ''' + @BillingAddressCountry + ''' could not be found'
				SET @ErrorMessageParameters = '{"country":"' + REPLACE(REPLACE(@BillingAddressCountry, '\', '\\'), '"', '\"') + '"}'
				GOTO _ROLLBACK
			END
			INSERT INTO [Address]
			(
				CompanyName,
				AddressLine1,
				AddressLine2,
				AddressLine3,
				City,
				County,
				Postcode,
				CountryID
			)
			VALUES
			(
				@ShippingAddressCompanyName,
				@ShippingAddressLine1,
				@ShippingAddressLine2,
				@ShippingAddressLine3,
				@ShippingAddressCity,
				@ShippingAddressCounty,
				@ShippingAddressPostcode,
				@ShippingAddressCountryID
			)
			DECLARE @ShippingAddressID INT = SCOPE_IDENTITY()
			INSERT INTO [Address]
			(
				AddressLine1,
				AddressLine2,
				City,
				County,
				Postcode,
				CountryID
			)
			VALUES
			(
				@BillingAddressLine1,
				@BillingAddressLine2,
				@BillingAddressCity,
				@BillingAddressCounty,
				@BillingAddressPostcode,
				@BillingAddressCountryID
			)
			DECLARE @BillingAddressID INT = SCOPE_IDENTITY()
			INSERT INTO [Customer]
			(
				ChannelID,
				Title,
				FirstName,
				LastName,
				ShippingAddressID,
				BillingAddressID,
				Email,
				Phone
			)
			VALUES
			(
				@ChannelID,
				@ShippingCustomerTitle,
				@ShippingCustomerFirstName,
				@ShippingCustomerLastName,
				@ShippingAddressID,
				@BillingAddressID,
				@ShippingCustomerEmail,
				@ShippingCustomerPhone
			)
			DECLARE @CustomerID INT = SCOPE_IDENTITY()
-- BEGIN PRODUCTS
			DECLARE @OrderedProducts TABLE
			(
				SKU NVARCHAR(100),
				Name NVARCHAR(800),
				UnitPrice MONEY,
				UnitWeightKG DECIMAL(19, 4),
				Quantity INT
			)
			DELETE FROM @OrderedProducts
			-- If the current row includes product information, insert it in to the @Products table:
			IF @ProductSKU IS NOT NULL AND @ProductSKU != ''
			BEGIN
				INSERT INTO @OrderedProducts
				(
					SKU,
					Name,
					UnitPrice,
					UnitWeightKG,
					Quantity
				)
				VALUES
				(
					@ProductSKU,
					CASE WHEN @ProductName IS NULL OR @ProductName = '' THEN @ProductSKU ELSE @ProductName END,
					@ProductUnitPrice,
					@ProductUnitWeightKG,
					@ProductQuantity
				)
			END
			-- For any rows with the same OrderReference, also insert that product information in to the @Products table:
			IF @OrderReference IS NOT NULL AND @OrderReference != ''
			BEGIN
				INSERT INTO @OrderedProducts
				(
					SKU,
					Name,
					UnitPrice,
					UnitWeightKG,
					Quantity
				)
				SELECT
					LTRIM(RTRIM(ProductSKU)),
					CASE WHEN ProductName IS NULL OR LTRIM(RTRIM(ProductName)) = '' THEN LTRIM(RTRIM(ProductSKU)) ELSE LTRIM(RTRIM(ProductName)) END,
					ProductUnitPrice,
					ProductUnitWeightKG,
					ProductQuantity
				FROM
					OrderImportItem
				WHERE
					OrderImportID = @OrderImportID
					AND LTRIM(RTRIM(OrderReference)) = @OrderReference
					AND LTRIM(RTRIM(ProductSKU)) IS NOT NULL
					AND LTRIM(RTRIM(ProductSKU)) != ''
					AND SpreadsheetRowIndex != @SpreadsheetRowIndex
			END
			IF (SELECT COUNT(*) FROM @OrderedProducts) > 0
			BEGIN
				DECLARE @NewProducts TABLE
				(
					ProductID INT,
					Price MONEY
				)
				DELETE FROM @NewProducts
				-- Create any necessary new products:
				INSERT INTO Product
				(
					AccountID,
					SKU,
					Name,
					Inventory,
					PackagingID,
					Price,
					PackageWeightKG,
					OrderImportID
				)
				OUTPUT
					inserted.ProductID,
					inserted.Price
				INTO
					@NewProducts
				SELECT
					@AccountID,
					SKU,
					Name,
					0,
					0,
					ISNULL(UnitPrice, 0),
					ISNULL(UnitWeightKG, 0),
					@OrderImportID
				FROM
					@OrderedProducts AS op
				WHERE
					NOT EXISTS (SELECT * FROM Product AS p WHERE AccountID = @AccountID AND LTRIM(RTRIM(p.SKU)) = op.SKU AND p.IsDeleted = 0)
				-- For any new products, add entries to ProductLog:
				INSERT INTO ProductLog
				(
					ProductID,
					LoggedUserID,
					Price,
					LastUpdateDate
				)
				SELECT
					ProductID,
					@LoggedUserID,
					Price,
					GETUTCDATE()
				FROM
					@NewProducts
				-- @OrderedProducts contains the products as they're described in the spreadsheet. We can now fill in the blanks from the products in the database:
				DECLARE @ActualOrderedProducts TABLE
				(
					ProductID INT,
					SKU NVARCHAR(100),
					Name NVARCHAR(800),
					UnitPrice MONEY,
					UnitWeightKG DECIMAL(19, 4),
					Quantity INT
				)
				DELETE FROM @ActualOrderedProducts
				INSERT INTO @ActualOrderedProducts
				(
					ProductID,
					SKU,
					Name,
					UnitPrice,
					UnitWeightKG,
					Quantity
				)
				SELECT
					p.ProductID,
					LTRIM(RTRIM(p.SKU)),
					ISNULL(LTRIM(RTRIM(op.Name)), LTRIM(RTRIM(p.Name))),
					ISNULL(op.UnitPrice, p.Price),
					ISNULL(op.UnitWeightKG, p.PackageWeightKG),
					ISNULL(op.Quantity, 0)
				FROM
					@OrderedProducts AS op
					INNER JOIN Product AS p ON p.AccountID = @AccountID AND LTRIM(RTRIM(p.SKU)) = op.SKU AND p.IsDeleted = 0
				-- If OrderWeightKG hasn't been explicitly defined for this order, calculate it based on the products:
				IF @OrderWeightKG IS NULL
				BEGIN
					SET @OrderWeightKG = (SELECT SUM(UnitWeightKG * Quantity) FROM @ActualOrderedProducts)
				END
				---- If OrderSubtotal hasn't been explicitly defined for this order, calculate it based on the products:
				IF @OrderSubtotal IS NULL
				BEGIN
					SET @OrderSubtotal = (SELECT SUM(UnitPrice * Quantity) FROM @ActualOrderedProducts)
				END
				---- If OrderTotal hasn't been explicitly defined for this order, calculate it based on the products:
				IF @OrderTotal IS NULL
				BEGIN
					SET @OrderTotal = (SELECT SUM(UnitPrice * Quantity) FROM @ActualOrderedProducts)
				END
			END
-- END PRODUCTS
			-- Get the shipping service ID based on shipping rules:
			DECLARE @ShippingServiceID INT = dbo.GetConvertedServiceID
			(
				@AccountID,
				@OrderTotal,
				@OrderShippingCost,
				@OrderWeightKG,
				@OrderPackagingID,
				@ChannelID,
				NULL,
				@ShippingAddressCountryID
			)
			INSERT INTO [Order]
			(
				AccountID,
				ChannelID,
				CustomerID,
				FirstName,
				LastName,
				ShippingAddressID,
				BillingAddressID,
				ShippingServiceID,
				ChannelOrderRef,
				SpecialInstructions,
				OrderDate,
				OrderWeightKG,
				PackagingID,
				OrderSubtotal,
				OrderShippingCosts,
				OrderTotal,
                OrderImportId
			)
			VALUES
			(
				@AccountID,
				@ChannelID,
				@CustomerID,
				@ShippingCustomerFirstName,
				@ShippingCustomerLastName,
				@ShippingAddressID,
				@BillingAddressID,
				@ShippingServiceID,
				@OrderReference,
				@OrderSpecialInstructions,
				@OrderDate,
				ISNULL(@OrderWeightKG, 0),
				ISNULL(@OrderPackagingID, 0),
				ISNULL(@OrderSubtotal, 0),
				ISNULL(@OrderShippingCost, 0),
				ISNULL(@OrderTotal, 0),
                @OrderImportId
			)
			DECLARE @OrderID INT = SCOPE_IDENTITY()
			INSERT INTO OrderLog
			(
				OrderID,
				OrderStatusID,
				LastUpdateDate,
				LoggedUserID
			)
			VALUES
			(
				@OrderID,
				1, -- Received
				GETUTCDATE(),
				@LoggedUserID
			)
			IF (SELECT COUNT(*) FROM @ActualOrderedProducts) > 0
			BEGIN
				-- Add order lines to the new order:
				INSERT INTO OrderLine
				(
					OrderID,
					ProductID,
					OrderedProductSKU,
					OrderedProductName,
					OrderedProductWeight,
					Quantity,
					SinglePrice,
					LineSubtotal,
					LineTotal
				)
				SELECT
					@OrderID,
					ProductID,
					SKU,
					Name,
					UnitWeightKG,
					Quantity,
					UnitPrice,
					Quantity * UnitPrice,
					Quantity * UnitPrice
				FROM
					@ActualOrderedProducts
			END
			IF @@TRANCOUNT > 0 COMMIT TRAN
			SET @SuccessCount = @SuccessCount + 1
			GOTO _END
		END TRY
		BEGIN CATCH
			SET @ErrorType = 1 -- Default (unknown / unexpected)
			SET @ErrorMessage = ERROR_MESSAGE()
		END CATCH
_ROLLBACK:
		SET @ErrorCount = @ErrorCount + 1
		IF @@TRANCOUNT > 0 ROLLBACK TRAN
		IF @ErrorType IS NOT NULL AND @ErrorMessage IS NOT NULL
		BEGIN
			BEGIN TRY
				INSERT INTO OrderImportError
				(
					OrderImportID,
					RowIndex,
					ErrorType,
					ErrorMessage,
					DisplayMessageParameters
				)
				VALUES
				(
					@OrderImportID,
					@SpreadsheetRowIndex,
					@ErrorType,
					@ErrorMessage,
					@ErrorMessageParameters
				)
			END TRY
			BEGIN CATCH
			END CATCH
		END
_END:
		FETCH NEXT FROM OrderImportItemCursor INTO
			@SpreadsheetRowIndex,
			@OrderReference,
			@OrderSpecialInstructions,
			@OrderDate,
			@OrderWeightKG,
			@OrderSubtotal,
			@OrderShippingCost,
			@OrderTotal,
			@OrderPackagingID,
			@ShippingCustomerTitle,
			@ShippingCustomerFirstName,
			@ShippingCustomerLastName,
			@ShippingCustomerPhone,
			@ShippingCustomerEmail,
			@ShippingAddressCompanyName,
			@ShippingAddressLine1,
			@ShippingAddressLine2,
			@ShippingAddressLine3,
			@ShippingAddressCity,
			@ShippingAddressCounty,
			@ShippingAddressPostcode,
			@ShippingAddressCountry,
			@BillingAddressCompanyName,
			@BillingAddressLine1,
			@BillingAddressLine2,
			@BillingAddressLine3,
			@BillingAddressCity,
			@BillingAddressCounty,
			@BillingAddressPostcode,
			@BillingAddressCountry,
			@ProductSKU,
			@ProductName,
			@ProductUnitPrice,
			@ProductUnitWeightKG,
			@ProductQuantity
	END
	CLOSE OrderImportItemCursor
	DEALLOCATE OrderImportItemCursor
	DELETE FROM
		OrderImportItem
	WHERE
		OrderImportID = @OrderImportID
END
