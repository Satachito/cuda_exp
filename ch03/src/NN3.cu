using namespace std;

template < typename F > struct
vArray {

	F*		_;
	size_t	n;

	vArray( F* _, size_t n )
	:	_( _ )
	,	n( n ) {
	}
	__host__ __device__ F&
	operator[]( size_t I ) const {
		return _[ I ];
	}
};

template < typename F > struct
Array	: vArray< F > {
	~
	Array() {
		cudaFree( vArray< F >::_ );
	}

	static	F*
	Malloc( size_t N ) {
		F*	_;
		cudaMallocManaged( &_, N * sizeof( F ) );
		return _;
	}
	Array( size_t n )
	:	vArray< F >( Malloc( n ), n ) {
	}
};

template < typename F > struct
vMatrix {

	F*		_;
	size_t	h;
	size_t	w;
	size_t	v;

	vMatrix( F* _, size_t h, size_t w, size_t v )
	:	_( _ )
	,	h( h )
	,	w( w )
	,	v( v ) {
	}

	__host__ __device__ F&
	operator()( size_t Y, size_t X ) const {
		return _[ Y * v + X ];
	}
	vArray< F >
	operator[]( size_t I ) const {
		return vArray< F >(
			_ + I * v
		,	w
		);
	}
};
#include <iostream>
template	< typename F >	ostream&
operator <<( ostream& S, const vMatrix< F >& P ) {
	for ( size_t y = 0; y < P.h; y++ ) {
		for ( size_t x = 0; x < P.w; x++ ) S << "	" << P( y, x );
		S << endl;
	}
	return S;
}

template < typename F > struct
Matrix	: vMatrix< F > {
	~
	Matrix() {
		cudaFree( vMatrix< F >::_ );
	}

	static	F*
	Malloc( size_t N ) {
		F*	_;
		cudaMallocManaged( &_, N * sizeof( F ) );
		return _;
	}
	Matrix( size_t h, size_t w )
	:	vMatrix< F >( Malloc( h * w ), h, w, w ) {
	}

	Matrix( const vMatrix< F >& _ )
	:	vMatrix< F >( Malloc( _.h * _.w ), _.h, _.w, _.w ) {
		for ( size_t y = 0; y < _.h; y++ ) for ( size_t x = 0; x < _.w; x++ ) (*this)( y, x ) = _( y, x );
	}

	Matrix( const Matrix< F >& _ )
	:	Matrix< F >( (vMatrix< F >)_ ) {
	}
};

#define	UNITS( p, q )	( ( p + q - 1 ) / q )

#define	B_S		256

inline	dim3
grid1D( size_t N ) {
	return dim3( UNITS( N, B_S ) );
}
inline	dim3
thread1D() {
	return dim3( B_S );
}

#define	B_S_H	32
#define	B_S_W	32

inline	dim3
grid2D( size_t H, size_t W ) {
	return dim3( UNITS( W, B_S_W ), UNITS( H, B_S_H ) );
}
inline	dim3
thread2D() {
	return dim3( B_S_W, B_S_H );
}

#include	<vector>

template	< typename F, int Y, int X >	Matrix< F >
MakeMatrix( initializer_list< F > args ) {
	vector< F >	argsV = args;
	Matrix< F > _( Y, X );
	for ( size_t y = 0; y < Y; y++ ) {
		for ( size_t x = 0; x < X; x++ ) {
			_( y, x ) = argsV[ y * X + x ];
		}
	}
	return _;
}

////////////////////////////////////////////////////////////////////////////////	3.2.4
template	< typename F >	__global__	void
SIGMOID( vMatrix< F > V, vMatrix< F >  P ) {
	auto y = (size_t)blockIdx.y * blockDim.y + threadIdx.y;	if ( y >= V.h ) return;
	auto x = (size_t)blockIdx.x * blockDim.x + threadIdx.x;	if ( x >= V.w ) return;
	V( y, x ) = 1 / ( 1 + exp( - P( y, x ) ) );
}
template	< typename F >	Matrix< F >
sigmoid( const vMatrix< F >& P ) {
	Matrix< F >	v( P.h, P.w );
	SIGMOID<<< grid2D( v.h, v.w ), thread2D() >>>( v, P );
	cudaDeviceSynchronize();
	return v;
}

template	< typename F >	void
_3_2_4() {
	cout << "3.2.4 sigmoid" << endl;
	cout << sigmoid( MakeMatrix< F, 2, 5 >( { -1, -0.5, 0, 0.5, 1, -1, -0.5, 0, 0.5, 1 } ) );
}

////////////////////////////////////////////////////////////////////////////////	3.2.7
template	< typename F >	__global__	void
RELU( vMatrix< F > V, vMatrix< F >  P ) {
	auto y = (size_t)blockIdx.y * blockDim.y + threadIdx.y;	if ( y >= V.h ) return;
	auto x = (size_t)blockIdx.x * blockDim.x + threadIdx.x;	if ( x >= V.w ) return;
	V( y, x ) = max( F( 0 ), P( y, x ) );
}
template	< typename F >	Matrix< F >
ReLU( const vMatrix< F >& P ) {
	Matrix< F >	v( P.h, P.w );
	RELU<<< grid2D( v.h, v.w ), thread2D() >>>( v, P );
	cudaDeviceSynchronize();
	return v;
}

template	< typename F >	void
_3_2_7() {
	cout << "3.2.7 ReLU" << endl;
	cout << ReLU( MakeMatrix< F, 2, 5 >( { -1, -0.5, 0, 0.5, 1, -1, -0.5, 0, 0.5, 1 } ) );
}

////////////////////////////////////////////////////////////////////////////////	3.3.2
template	< typename F >	__global__	void
DOT( vMatrix< F > V, vMatrix< F > L, vMatrix< F > R, size_t WH ) {
	auto y = (size_t)blockIdx.y * blockDim.y + threadIdx.y;	if ( y >= V.h ) return;
	auto x = (size_t)blockIdx.x * blockDim.x + threadIdx.x;	if ( x >= V.w ) return;
	auto lp = L._ + y * L.v;
	auto rp = R._ + x;
	F w = 0;
	for ( size_t _ = 0; _ < WH; _++ ) w += lp[ _ ] * rp[ _ * R.v ];
	V( y, x ) = w;
}
template	< typename F >	Matrix< F >
operator *( const vMatrix< F >& L, const vMatrix< F >& R ) {
	Matrix< F >	v( L.h, R.w );
	DOT<<< grid2D( v.h, v.w ), thread2D() >>>( v, L, R, L.w );
	cudaDeviceSynchronize();
	return v;
}

template	< typename F >	void
_3_3_2() {
	cout << "3.3.2 dot operation" << endl;
	auto l = MakeMatrix< F, 2, 3 >( { 1, 2, 3, 4, 5, 6 } );
	auto r = MakeMatrix< F, 3, 2 >( { 1, 2, 3, 4, 5, 6 } );
	cout << l * r;
}


////////////////////////////////////////////////////////////////////////////////	3.4.3
#include	<map>

template	< typename F >	map< string, Matrix< F > >
init_network_3_4_3() {
	map< string, Matrix< F > >	_;
	_.emplace( "W1", MakeMatrix< F, 2, 3 >( { 0.1, 0.3, 0.5, 0.2, 0.4, 0.6 } ) );
	_.emplace( "b1", MakeMatrix< F, 1, 3 >( { 0.1, 0.2, 0.3 } ) );
	_.emplace( "W2", MakeMatrix< F, 3, 2 >( { 0.1, 0.4, 0.2, 0.5, 0.3, 0.6 } ) );
	_.emplace( "b2", MakeMatrix< F, 1, 2 >( { 0.1, 0.2 } ) );
	_.emplace( "W3", MakeMatrix< F, 2, 2 >( { 0.1, 0.3, 0.2, 0.4 } ) );
	_.emplace( "b3", MakeMatrix< F, 1, 2 >( { 0.1, 0.2 } ) );
	return _;
}

template	< typename F >	Matrix< F >
identify_function( const Matrix< F >& _ ) {
	return _;
}

template	< typename F >	__global__	void
ADD( vMatrix< F > V, vMatrix< F > L, vMatrix< F > R ) {
	auto y = (size_t)blockIdx.y * blockDim.y + threadIdx.y;	if ( y >= V.h ) return;
	auto x = (size_t)blockIdx.x * blockDim.x + threadIdx.x;	if ( x >= V.w ) return;
	V( y, x ) = L( y, x ) + R( y, x );
}
template	< typename F >	Matrix< F >
operator +( const vMatrix< F >& L, const vMatrix< F >& R ) {
	Matrix< F >	v( L.h, R.w );
	ADD<<< grid2D( v.h, v.w ), thread2D() >>>( v, L, R );
	cudaDeviceSynchronize();
	return v;
}

template	< typename F >	Matrix< F >
forward( map< string, Matrix< F > >& network, const vMatrix< F >& x ) {
	auto W1 = network.at( "W1" );
	auto W2 = network.at( "W2" );
	auto W3 = network.at( "W3" );
	auto b1 = network.at( "b1" );
	auto b2 = network.at( "b2" );
	auto b3 = network.at( "b3" );

	auto a1 = x * W1 + b1;
	auto z1 = sigmoid( a1 );
	auto a2 = z1 * W2 + b2;
	auto z2 = sigmoid( a2 );
	auto a3 = z2 * W3 + b3;
	auto y = identify_function( a3 );
	return y;
}

template	< typename F >	void
_3_4_3() {
	cout << "3.4.3 neural" << endl;
	auto network = init_network_3_4_3< F >();
	auto x = MakeMatrix< F, 1, 2 >( { 1.0, 0.5 } );
	auto y = forward( network, x );
	cout << y;
}

////////////////////////////////////////////////////////////////////////////////	3.5.1
template	< typename F >	__global__	void
EXP( vMatrix< F > V, vMatrix< F >  P ) {
	auto y = (size_t)blockIdx.y * blockDim.y + threadIdx.y;	if ( y >= V.h ) return;
	auto x = (size_t)blockIdx.x * blockDim.x + threadIdx.x;	if ( x >= V.w ) return;
	V( y, x ) = exp( P( y, x ) );
}
template	< typename F >	Matrix< F >
exp( const vMatrix< F >& P ) {
	Matrix< F >	v( P.h, P.w );
	EXP<<< grid2D( v.h, v.w ), thread2D() >>>( v, P );
	cudaDeviceSynchronize();
	return v;
}

template	< typename F >	F
sum( const vMatrix< F >& P ) {
	F	_ = 0;
	for ( size_t y = 0; y < P.h; y++ ) for ( size_t x = 0; x < P.w; x++ ) _ += P( y, x );
	return _;
}

template	< typename F >	__global__	void
DIV_INP( vMatrix< F > V, F P ) {
	auto y = (size_t)blockIdx.y * blockDim.y + threadIdx.y;	if ( y >= V.h ) return;
	auto x = (size_t)blockIdx.x * blockDim.x + threadIdx.x;	if ( x >= V.w ) return;
	V( y, x ) /= P;
}
template	< typename F >	void
operator /=( const vMatrix< F >& L, F R ) {
	DIV_INP<<< grid2D( L.h, L.w ), thread2D() >>>( L, R );
	cudaDeviceSynchronize();
}

template	< typename F >	Matrix< F >
softmax_primitive( const vMatrix< F >& p ) {
	auto v = exp( p );
	v /= sum( v );
	return v;
}
template	< typename F >	void
_3_5_1() {
	cout << "3.5.1 softmax_primitive" << endl;
	cout << softmax_primitive( MakeMatrix< F, 1, 3 >( { 0.3, 2.9, 4.0 } ) );
}

////////////////////////////////////////////////////////////////////////////////	3.5.2
template	< typename F >	F
max( const vMatrix< F >& P ) {
	F	_ = P( 0, 0 );
	for ( size_t y = 0; y < P.h; y++ ) for ( size_t x = 0; x < P.w; x++ ) if ( P( y, x ) > _ ) _ = P( y, x );
	return _;
}

template	< typename F >	__global__	void
SUB_C( vMatrix< F > V, vMatrix< F > L, F R ) {
	auto y = (size_t)blockIdx.y * blockDim.y + threadIdx.y;	if ( y >= V.h ) return;
	auto x = (size_t)blockIdx.x * blockDim.x + threadIdx.x;	if ( x >= V.w ) return;
	V( y, x ) = L( y, x ) - R;
}
template	< typename F >	Matrix< F >
operator -( const vMatrix< F >& L, F R ) {
	Matrix< F >	v( L.h, L.w );
	SUB_C<<< grid2D( v.h, v.w ), thread2D() >>>( v, L, R );
	cudaDeviceSynchronize();
	return v;
}

template	< typename F >	Matrix< F >
softmax( const vMatrix< F >& p ) {
	auto v = exp( p - max( p ) );
	v /= sum( v );
	return v;
}
template	< typename F >	void
_3_5_2() {
	cout << "3.5.2 softmax" << endl;
	cout << softmax( MakeMatrix< F, 1, 3 >( { 1010, 1000, 990 } ) );
}

////////////////////////////////////////////////////////////////////////////////	3.5.3
template	< typename F >	void
_3_5_3() {
	cout << "3.5.3 sum( softmax )" << endl;
	cout << sum( softmax( MakeMatrix< F, 1, 3 >( { 0.3, 2.9, 4.0 } ) ) ) << endl;
}

////////////////////////////////////////////////////////////////////////////////	3.6.1
#include	<fstream>

template	< typename F >	map< string, Matrix< F > >
get_data() {
	map< string, Matrix< F > > v;
	{	ifstream ifs( "../train-images.idx3-ubyte" );
		if ( ! ifs.is_open() ) throw "../train-images.idx3-ubyte";
		ifs.ignore( 16 );
		Matrix< F > w( 60000, 28 * 28 );
		for ( size_t _ = 0; _ < w.h * w.w; _++ ) w._[ _ ] = ( (unsigned char)ifs.get() ) / 255.0;
		v.emplace( "x_train", w );
	}
	{	ifstream ifs( "../train-labels.idx1-ubyte" );
		if ( ! ifs.is_open() ) throw "../train-labels.idx1-ubyte";
		ifs.ignore( 8 );
		Matrix< F > w( 1, 60000 );
		for ( size_t _ = 0; _ < w.h * w.w; _++ ) w._[ _ ] = ifs.get();
		v.emplace( "t_train", w );
	}
	{	ifstream ifs( "../t10k-images.idx3-ubyte" );
		if ( ! ifs.is_open() ) throw "../t10k-images.idx3-ubyte";
		ifs.ignore( 16 );
		Matrix< F > w( 10000, 28 * 28 );
		for ( size_t _ = 0; _ < w.h * w.w; _++ ) w._[ _ ] = ( (unsigned char)ifs.get() ) / 255.0;
		v.emplace( "x_test", w );
	}
	{	ifstream ifs( "../t10k-labels.idx1-ubyte" );
		if ( ! ifs.is_open() ) throw "../t10k-labels.idx1-ubyte";
		ifs.ignore( 8 );
		Matrix< F > w( 1, 10000 );
		for ( size_t _ = 0; _ < w.h * w.w; _++ ) w._[ _ ] = ifs.get();
		v.emplace( "t_test", w );
	}
	return v;
}

map< string, Matrix< double > >
init_network() {
	map< string, Matrix< double > > v;
	ifstream	ifs( "../sample_weight.bin" );
	if ( ! ifs.is_open() ) throw "../sample_weight.bin";

	{	Matrix< double > w( 784, 50 );
		ifs.read( (char*)w._, w.h * w.w * sizeof( double ) );
		v.emplace( "W1", w );
	}
	{	Matrix< double > w( 50, 100 );
		ifs.read( (char*)w._, w.h * w.w * sizeof( double ) );
		v.emplace( "W2", w );
	}
	{	Matrix< double > w( 100, 10 );
		ifs.read( (char*)w._, w.h * w.w * sizeof( double ) );
		v.emplace( "W3", w );
	}

	{	Matrix< double > w( 1, 50 );
		ifs.read( (char*)w._, w.h * w.w * sizeof( double ) );
		v.emplace( "b1", w );
	}
	{	Matrix< double > w( 1, 100 );
		ifs.read( (char*)w._, w.h * w.w * sizeof( double ) );
		v.emplace( "b2", w );
	}
	{	Matrix< double > w( 1, 10 );
		ifs.read( (char*)w._, w.h * w.w * sizeof( double ) );
		v.emplace( "b3", w );
	}

	return v;
}
template	< typename F >	__global__	void
ADD( vMatrix< F > V, vMatrix< F > L, vArray< F > R ) {
	auto y = (size_t)blockIdx.y * blockDim.y + threadIdx.y;	if ( y >= V.h ) return;
	auto x = (size_t)blockIdx.x * blockDim.x + threadIdx.x;	if ( x >= V.w ) return;
	V( y, x ) = L( y, x ) + R[ x ];
}
template	< typename F >	Matrix< F >
operator +( const vMatrix< F >& L, const vArray< F >& R ) {
	Matrix< F >	v( L.h, L.w );
	ADD<<< grid2D( v.h, v.w ), thread2D() >>>( v, L, R );
	cudaDeviceSynchronize();
	return v;
}
template	< typename F >	Matrix< F >
predict( map< string, Matrix< F > >& network, const vMatrix< F >& x ) {
	Matrix< F >& W1 = network.at( "W1" );
	Matrix< F >& W2 = network.at( "W2" );
	Matrix< F >& W3 = network.at( "W3" );
	auto b1 = network.at( "b1" )[ 0 ];
	auto b2 = network.at( "b2" )[ 0 ];
	auto b3 = network.at( "b3" )[ 0 ];

	auto a1 = x * W1 + b1;
	auto z1 = sigmoid( a1 );
	auto a2 = z1 * W2 + b2;
	auto z2 = sigmoid( a2 );
	auto a3 = z2 * W3 + b3;
	auto y = softmax( a3 );
	return y;
}

template	< typename F >	F
argmax( const vArray< F >& P ) {
	size_t	_ = 0;
	for ( size_t i = 1; i < P.n; i++ ) if ( P[ i ] > P[ _ ] ) _ = i;
	return F( _ );
}

template	< typename F >	Array< F >
argmax( const vMatrix< F >& P ) {
	Array< F >	_( P.h );
	for ( size_t y = 0; y < P.h; y++ ) _[ y ] = argmax( P[ y ] );
	return _;
}

template	< typename F >	vArray< F >
Part( const vArray< F >& _, size_t O, size_t N ) {
	return vArray< F >(
		_._ + O
	,	N
	);
}
template	< typename F >	vMatrix< F >
Part( const vMatrix< F >& _, size_t Y, size_t X, size_t H, size_t W ) {
	return vMatrix< F >(
		_._ + Y * _.v + X
	,	H
	,	W
	,	_.v
	);
}

void
_3_6_1() {
	cout << "3.6.1 MNIST" << endl;
	auto w = get_data< double >();
	auto x_test = w.at( "x_test" );
	auto t_test = w.at( "t_test" )[ 0 ];
	auto network = init_network();
	auto accuracy_cnt = 0;
	for ( size_t i = 0; i < x_test.h; i++ ) {
		auto y = predict( network, Part( x_test, i, 0, 1, x_test.w ) );
		auto p = argmax( y[ 0 ] );
		if ( p == t_test[ i ] ) accuracy_cnt++;
	}
	cout << "accuracy_cnt: " << ( ( double)accuracy_cnt / (double)x_test.h ) << endl;
}

////////////////////////////////////////////////////////////////////////////////	3.6.3
template < typename F > size_t
CountEquals( const vArray< F >& L, const vArray< F >& R ) {
	size_t _ = 0;
	for ( size_t i = 0; i < L.n; i++ ) if ( L[ i ] == R[ i ] ) _++;
	return _;
}

void
_3_6_3() {
	cout << "3.6.3 MNIST BATCH" << endl;
	auto w = get_data< double >();
	auto x_test = w.at( "x_test" );
	auto t_test = w.at( "t_test" )[ 0 ];
	auto network = init_network();
	auto accuracy_cnt = 0;
	for ( size_t i = 0; i < x_test.h; i += 100 ) {
		auto y = predict( network, Part( x_test, i, 0, 100, x_test.w ) );
		auto p = argmax( y );
		accuracy_cnt += CountEquals( p, Part( t_test, i, 100 ) );
	}
	cout << "accuracy_cnt: " << ( ( double)accuracy_cnt / (double)x_test.h ) << endl;
}

////////////////////////////////////////////////////////////////////////////////	Main
template	< typename F >	void
Main() {
	_3_2_4< F >();
	_3_2_7< F >();
	_3_3_2< F >();
	_3_4_3< F >();
	_3_5_1< F >();
	_3_5_2< F >();
	_3_5_3< F >();
	_3_6_1();
	_3_6_3();
}
int
main( int argc, char* argv[] ) {
	Main< double >();
}

