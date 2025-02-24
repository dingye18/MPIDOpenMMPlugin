extern "C" __global__ void computeLabFrameMoments(real4* __restrict__ posq, int4* __restrict__ multipoleParticles, float* __restrict__ molecularDipoles,
        float* __restrict__ molecularQuadrupoles, float* __restrict__ molecularOctopoles, real* __restrict__ labFrameDipoles, real* __restrict__ labFrameQuadrupoles,
        real* __restrict__ labFrameOctopoles, real* __restrict__ sphericalDipoles, real* __restrict__ sphericalQuadrupoles, real* __restrict__ sphericalOctopoles,
        float* __restrict__ polarizability, real* __restrict__ labFramePolarizabilities) {
    for (int atom = blockIdx.x*blockDim.x+threadIdx.x; atom < NUM_ATOMS; atom += gridDim.x*blockDim.x) {
        // Load the spherical multipoles.

        int offset = 3*atom;
        sphericalDipoles[offset+0] = molecularDipoles[offset+2]; // z -> Q_10
        sphericalDipoles[offset+1] = molecularDipoles[offset+0]; // x -> Q_11c
        sphericalDipoles[offset+2] = molecularDipoles[offset+1]; // y -> Q_11s
        offset = 5*atom;
        sphericalQuadrupoles[offset+0] = -3.0f*(molecularQuadrupoles[offset+0]+molecularQuadrupoles[offset+3]); // zz -> Q_20
        sphericalQuadrupoles[offset+1] = (2*SQRT((real) 3))*molecularQuadrupoles[offset+2]; // xz -> Q_21c
        sphericalQuadrupoles[offset+2] = (2*SQRT((real) 3))*molecularQuadrupoles[offset+4]; // yz -> Q_21s
        sphericalQuadrupoles[offset+3] = SQRT((real) 3)*(molecularQuadrupoles[offset+0]-molecularQuadrupoles[offset+3]); // xx-yy -> Q_22c
        sphericalQuadrupoles[offset+4] = (2*SQRT((real) 3))*molecularQuadrupoles[offset+1]; // xy -> Q_22s
        offset = 7*atom;
        sphericalOctopoles[offset+0] = -15.0f*(molecularOctopoles[offset+2]+molecularOctopoles[offset+6]); // zzz -> Q_30
        sphericalOctopoles[offset+1] = -15.0f*SQRT((real) 1.5f)*(molecularOctopoles[offset+0]+molecularOctopoles[offset+3]); // xzz -> Q_31c
        sphericalOctopoles[offset+2] = -15.0f*SQRT((real) 1.5f)*(molecularOctopoles[offset+1]+molecularOctopoles[offset+5]); // yzz -> Q_31s
        sphericalOctopoles[offset+3] =  15.0f*SQRT((real) 0.6f)*(molecularOctopoles[offset+2]-molecularOctopoles[offset+6]); // xxz-yyz -> Q_32c
        sphericalOctopoles[offset+4] =  30.0f*SQRT((real) 0.6f)*molecularOctopoles[offset+4]; // xyz -> Q_32s
        sphericalOctopoles[offset+5] =  15.0f*SQRT((real) 0.1f)*(molecularOctopoles[offset+0]-3.0f*molecularOctopoles[offset+3]); // xxx-xyy -> Q_33c
        sphericalOctopoles[offset+6] =  15.0f*SQRT((real) 0.1f)*(3.0f*molecularOctopoles[offset+1]-molecularOctopoles[offset+5]); // xxy-yyy -> Q_33s

        // get coordinates of this atom and the z & x axis atoms
        // compute the vector between the atoms and 1/sqrt(d2), d2 is distance between
        // this atom and the axis atom

        // this atom is referred to as the k-atom in notes below

        // code common to ZThenX and Bisector
        int4 particles = multipoleParticles[atom];
        if (particles.z >= 0) {
            real4 thisParticlePos = posq[atom];
            real4 posZ = posq[particles.z];
            real3 vectorZ = normalize(make_real3(posZ.x-thisParticlePos.x, posZ.y-thisParticlePos.y, posZ.z-thisParticlePos.z));
            int axisType = particles.w;
            real4 posX;
            real3 vectorX;
            if (axisType >= 4) {
                if (fabs(vectorZ.x) < 0.866f)
                    vectorX = make_real3(1, 0, 0);
                else
                    vectorX = make_real3(0, 1, 0);
            }
            else {
                posX = posq[particles.x];
                vectorX = make_real3(posX.x-thisParticlePos.x, posX.y-thisParticlePos.y, posX.z-thisParticlePos.z);
            }

            /*
                z-only
                   (1) norm z
                   (2) select random x
                   (3) x = x - (x.z)z
                   (4) norm x

                z-then-x
                   (1) norm z
                   (2) norm x (not needed)
                   (3) x = x - (x.z)z
                   (4) norm x

                bisector
                   (1) norm z
                   (2) norm x
                   (3) z = x + z
                   (4) norm z
                   (5) x = x - (x.z)z
                   (6) norm x

                z-bisect
                   (1) norm z
                   (2) norm x
                   (3) norm y
                   (3) x = x + y
                   (4) norm x
                   (5) x = x - (x.z)z
                   (6) norm x

                3-fold
                   (1) norm z
                   (2) norm x
                   (3) norm y
                   (4) z = x + y + z
                   (5) norm z
                   (6) x = x - (x.z)z
                   (7) norm x
            */

            // branch based on axis type

            if (axisType == 1) {
                // bisector
                vectorX = normalize(vectorX);
                vectorZ += vectorX;
                vectorZ = normalize(vectorZ);
            }
            else if (axisType == 2 || axisType == 3) {
                // z-bisect
                if (particles.y >= 0 && particles.y < NUM_ATOMS) {
                    real4 posY = posq[particles.y];
                    real3 vectorY = make_real3(posY.x-thisParticlePos.x, posY.y-thisParticlePos.y, posY.z-thisParticlePos.z);
                    vectorY = normalize(vectorY);
                    vectorX = normalize(vectorX);
                    if (axisType == 2) {
                        vectorX += vectorY;
                        vectorX = normalize(vectorX);
                    }
                    else {
                        // 3-fold
                        vectorZ += vectorX + vectorY;
                        vectorZ = normalize(vectorZ);
                    }
                }
            }
            // x = x - (x.z)z
            vectorX -= dot(vectorZ, vectorX)*vectorZ;
            vectorX = normalize(vectorX);
            real3 vectorY = cross(vectorZ, vectorX);
            // use identity rotation matrix for unrecognized axis types
            if (axisType < 0 || axisType > 4) {
                vectorX.x = 1;
                vectorX.y = 0;
                vectorX.z = 0;

                vectorY.x = 0;
                vectorY.y = 1;
                vectorY.z = 0;

                vectorZ.x = 0;
                vectorZ.y = 0;
                vectorZ.z = 1;
            }
            // Check the chirality and see whether it needs to be reversed

            bool reverse = false;
            if (axisType == 0 && particles.x >= 0 && particles.y >=0 && particles.z >= 0) {
                real4 posY = posq[particles.y];
                real delta[4][3];

                delta[0][0] = thisParticlePos.x - posY.x;
                delta[0][1] = thisParticlePos.y - posY.y;
                delta[0][2] = thisParticlePos.z - posY.z;

                delta[1][0] = posZ.x - posY.x;
                delta[1][1] = posZ.y - posY.y;
                delta[1][2] = posZ.z - posY.z;

                delta[2][0] = posX.x - posY.x;
                delta[2][1] = posX.y - posY.y;
                delta[2][2] = posX.z - posY.z;

                delta[3][0] = delta[1][1]*delta[2][2] - delta[1][2]*delta[2][1];
                delta[3][1] = delta[2][1]*delta[0][2] - delta[2][2]*delta[0][1];
                delta[3][2] = delta[0][1]*delta[1][2] - delta[0][2]*delta[1][1];

                real volume = delta[3][0]*delta[0][0] + delta[3][1]*delta[1][0] + delta[3][2]*delta[2][0];
                reverse = (volume < 0);
            }

            // Transform the dipole

            offset = 3*atom;
            real molDipole[3];
            molDipole[0] = molecularDipoles[offset];
            molDipole[1] = molecularDipoles[offset+1];
            molDipole[2] = molecularDipoles[offset+2];
            if (reverse)
                molDipole[1] *= -1;
            labFrameDipoles[offset] = molDipole[0]*vectorX.x + molDipole[1]*vectorY.x + molDipole[2]*vectorZ.x;
            labFrameDipoles[offset+1] = molDipole[0]*vectorX.y + molDipole[1]*vectorY.y + molDipole[2]*vectorZ.y;
            labFrameDipoles[offset+2] = molDipole[0]*vectorX.z + molDipole[1]*vectorY.z + molDipole[2]*vectorZ.z;

            // ---------------------------------------------------------------------------------------

            // Transform the quadrupole

            offset = 5*atom;
            real mPoleXX = molecularQuadrupoles[offset];
            real mPoleXY = molecularQuadrupoles[offset+1];
            real mPoleXZ = molecularQuadrupoles[offset+2];
            real mPoleYY = molecularQuadrupoles[offset+3];
            real mPoleYZ = molecularQuadrupoles[offset+4];
            real mPoleZZ = -(mPoleXX+mPoleYY);

            if (reverse) {
                mPoleXY *= -1;
                mPoleYZ *= -1;
            }

            labFrameQuadrupoles[offset] = vectorX.x*(vectorX.x*mPoleXX + vectorY.x*mPoleXY + vectorZ.x*mPoleXZ)
                                        + vectorY.x*(vectorX.x*mPoleXY + vectorY.x*mPoleYY + vectorZ.x*mPoleYZ)
                                        + vectorZ.x*(vectorX.x*mPoleXZ + vectorY.x*mPoleYZ + vectorZ.x*mPoleZZ);
            labFrameQuadrupoles[offset+1] = vectorX.x*(vectorX.y*mPoleXX + vectorY.y*mPoleXY + vectorZ.y*mPoleXZ)
                                        + vectorY.x*(vectorX.y*mPoleXY + vectorY.y*mPoleYY + vectorZ.y*mPoleYZ)
                                        + vectorZ.x*(vectorX.y*mPoleXZ + vectorY.y*mPoleYZ + vectorZ.y*mPoleZZ);
            labFrameQuadrupoles[offset+2] = vectorX.x*(vectorX.z*mPoleXX + vectorY.z*mPoleXY + vectorZ.z*mPoleXZ)
                                        + vectorY.x*(vectorX.z*mPoleXY + vectorY.z*mPoleYY + vectorZ.z*mPoleYZ)
                                        + vectorZ.x*(vectorX.z*mPoleXZ + vectorY.z*mPoleYZ + vectorZ.z*mPoleZZ);
            labFrameQuadrupoles[offset+3] = vectorX.y*(vectorX.y*mPoleXX + vectorY.y*mPoleXY + vectorZ.y*mPoleXZ)
                                        + vectorY.y*(vectorX.y*mPoleXY + vectorY.y*mPoleYY + vectorZ.y*mPoleYZ)
                                        + vectorZ.y*(vectorX.y*mPoleXZ + vectorY.y*mPoleYZ + vectorZ.y*mPoleZZ);
            labFrameQuadrupoles[offset+4] = vectorX.y*(vectorX.z*mPoleXX + vectorY.z*mPoleXY + vectorZ.z*mPoleXZ)
                                        + vectorY.y*(vectorX.z*mPoleXY + vectorY.z*mPoleYY + vectorZ.z*mPoleYZ)
                                        + vectorZ.y*(vectorX.z*mPoleXZ + vectorY.z*mPoleYZ + vectorZ.z*mPoleZZ);


            // Transform the (diagonal) polarizability tensor
            offset = 3*atom;
            mPoleXX = polarizability[offset+0];
            mPoleYY = polarizability[offset+1];
            mPoleZZ = polarizability[offset+2];
            offset = 6*atom;
            labFramePolarizabilities[offset+0] = vectorX.x*vectorX.x*mPoleXX + vectorY.x*vectorY.x*mPoleYY + vectorZ.x*vectorZ.x*mPoleZZ;
            labFramePolarizabilities[offset+1] = vectorX.x*vectorX.y*mPoleXX + vectorY.x*vectorY.y*mPoleYY + vectorZ.x*vectorZ.y*mPoleZZ;
            labFramePolarizabilities[offset+2] = vectorX.x*vectorX.z*mPoleXX + vectorY.x*vectorY.z*mPoleYY + vectorZ.x*vectorZ.z*mPoleZZ;
            labFramePolarizabilities[offset+3] = vectorX.y*vectorX.y*mPoleXX + vectorY.y*vectorY.y*mPoleYY + vectorZ.y*vectorZ.y*mPoleZZ;
            labFramePolarizabilities[offset+4] = vectorX.y*vectorX.z*mPoleXX + vectorY.y*vectorY.z*mPoleYY + vectorZ.y*vectorZ.z*mPoleZZ;
            labFramePolarizabilities[offset+5] = vectorX.z*vectorX.z*mPoleXX + vectorY.z*vectorY.z*mPoleYY + vectorZ.z*vectorZ.z*mPoleZZ;

            // Transform the octopole

            offset = 7*atom;
            real mPoleXXX = molecularOctopoles[offset+0];
            real mPoleXXY = molecularOctopoles[offset+1];
            real mPoleXXZ = molecularOctopoles[offset+2];
            real mPoleXYY = molecularOctopoles[offset+3];
            real mPoleXYZ = molecularOctopoles[offset+4];
            real mPoleXZZ = -molecularOctopoles[offset+0]-molecularOctopoles[offset+3];
            real mPoleYYY = molecularOctopoles[offset+5];
            real mPoleYYZ = molecularOctopoles[offset+6];
            real mPoleYZZ = -molecularOctopoles[offset+1]-molecularOctopoles[offset+5];
            real mPoleZZZ = -molecularOctopoles[offset+2]-molecularOctopoles[offset+6];

            real T2XXX = vectorX.x*(vectorX.x*mPoleXXX + vectorY.x*mPoleXXY + vectorZ.x*mPoleXXZ)
                       + vectorY.x*(vectorX.x*mPoleXXY + vectorY.x*mPoleXYY + vectorZ.x*mPoleXYZ)
                       + vectorZ.x*(vectorX.x*mPoleXXZ + vectorY.x*mPoleXYZ + vectorZ.x*mPoleXZZ);
            real T2XXY = vectorX.x*(vectorX.y*mPoleXXX + vectorY.y*mPoleXXY + vectorZ.y*mPoleXXZ)
                       + vectorY.x*(vectorX.y*mPoleXXY + vectorY.y*mPoleXYY + vectorZ.y*mPoleXYZ)
                       + vectorZ.x*(vectorX.y*mPoleXXZ + vectorY.y*mPoleXYZ + vectorZ.y*mPoleXZZ);
            real T2XXZ = vectorX.x*(vectorX.z*mPoleXXX + vectorY.z*mPoleXXY + vectorZ.z*mPoleXXZ)
                       + vectorY.x*(vectorX.z*mPoleXXY + vectorY.z*mPoleXYY + vectorZ.z*mPoleXYZ)
                       + vectorZ.x*(vectorX.z*mPoleXXZ + vectorY.z*mPoleXYZ + vectorZ.z*mPoleXZZ);
            real T2XYY = vectorX.y*(vectorX.y*mPoleXXX + vectorY.y*mPoleXXY + vectorZ.y*mPoleXXZ)
                       + vectorY.y*(vectorX.y*mPoleXXY + vectorY.y*mPoleXYY + vectorZ.y*mPoleXYZ)
                       + vectorZ.y*(vectorX.y*mPoleXXZ + vectorY.y*mPoleXYZ + vectorZ.y*mPoleXZZ);
            real T2XYZ = vectorX.y*(vectorX.z*mPoleXXX + vectorY.z*mPoleXXY + vectorZ.z*mPoleXXZ)
                       + vectorY.y*(vectorX.z*mPoleXXY + vectorY.z*mPoleXYY + vectorZ.z*mPoleXYZ)
                       + vectorZ.y*(vectorX.z*mPoleXXZ + vectorY.z*mPoleXYZ + vectorZ.z*mPoleXZZ);
            real T2YXX = vectorX.x*(vectorX.x*mPoleXXY + vectorY.x*mPoleXYY + vectorZ.x*mPoleXYZ)
                       + vectorY.x*(vectorX.x*mPoleXYY + vectorY.x*mPoleYYY + vectorZ.x*mPoleYYZ)
                       + vectorZ.x*(vectorX.x*mPoleXYZ + vectorY.x*mPoleYYZ + vectorZ.x*mPoleYZZ);
            real T2YXY = vectorX.x*(vectorX.y*mPoleXXY + vectorY.y*mPoleXYY + vectorZ.y*mPoleXYZ)
                       + vectorY.x*(vectorX.y*mPoleXYY + vectorY.y*mPoleYYY + vectorZ.y*mPoleYYZ)
                       + vectorZ.x*(vectorX.y*mPoleXYZ + vectorY.y*mPoleYYZ + vectorZ.y*mPoleYZZ);
            real T2YXZ = vectorX.x*(vectorX.z*mPoleXXY + vectorY.z*mPoleXYY + vectorZ.z*mPoleXYZ)
                       + vectorY.x*(vectorX.z*mPoleXYY + vectorY.z*mPoleYYY + vectorZ.z*mPoleYYZ)
                       + vectorZ.x*(vectorX.z*mPoleXYZ + vectorY.z*mPoleYYZ + vectorZ.z*mPoleYZZ);
            real T2YYY = vectorX.y*(vectorX.y*mPoleXXY + vectorY.y*mPoleXYY + vectorZ.y*mPoleXYZ)
                       + vectorY.y*(vectorX.y*mPoleXYY + vectorY.y*mPoleYYY + vectorZ.y*mPoleYYZ)
                       + vectorZ.y*(vectorX.y*mPoleXYZ + vectorY.y*mPoleYYZ + vectorZ.y*mPoleYZZ);
            real T2YYZ = vectorX.y*(vectorX.z*mPoleXXY + vectorY.z*mPoleXYY + vectorZ.z*mPoleXYZ)
                       + vectorY.y*(vectorX.z*mPoleXYY + vectorY.z*mPoleYYY + vectorZ.z*mPoleYYZ)
                       + vectorZ.y*(vectorX.z*mPoleXYZ + vectorY.z*mPoleYYZ + vectorZ.z*mPoleYZZ);
            real T2ZXX = vectorX.x*(vectorX.x*mPoleXXZ + vectorY.x*mPoleXYZ + vectorZ.x*mPoleXZZ)
                       + vectorY.x*(vectorX.x*mPoleXYZ + vectorY.x*mPoleYYZ + vectorZ.x*mPoleYZZ)
                       + vectorZ.x*(vectorX.x*mPoleXZZ + vectorY.x*mPoleYZZ + vectorZ.x*mPoleZZZ);
            real T2ZXY = vectorX.x*(vectorX.y*mPoleXXZ + vectorY.y*mPoleXYZ + vectorZ.y*mPoleXZZ)
                       + vectorY.x*(vectorX.y*mPoleXYZ + vectorY.y*mPoleYYZ + vectorZ.y*mPoleYZZ)
                       + vectorZ.x*(vectorX.y*mPoleXZZ + vectorY.y*mPoleYZZ + vectorZ.y*mPoleZZZ);
            real T2ZXZ = vectorX.x*(vectorX.z*mPoleXXZ + vectorY.z*mPoleXYZ + vectorZ.z*mPoleXZZ)
                       + vectorY.x*(vectorX.z*mPoleXYZ + vectorY.z*mPoleYYZ + vectorZ.z*mPoleYZZ)
                       + vectorZ.x*(vectorX.z*mPoleXZZ + vectorY.z*mPoleYZZ + vectorZ.z*mPoleZZZ);
            real T2ZYY = vectorX.y*(vectorX.y*mPoleXXZ + vectorY.y*mPoleXYZ + vectorZ.y*mPoleXZZ)
                       + vectorY.y*(vectorX.y*mPoleXYZ + vectorY.y*mPoleYYZ + vectorZ.y*mPoleYZZ)
                       + vectorZ.y*(vectorX.y*mPoleXZZ + vectorY.y*mPoleYZZ + vectorZ.y*mPoleZZZ);
            real T2ZYZ = vectorX.y*(vectorX.z*mPoleXXZ + vectorY.z*mPoleXYZ + vectorZ.z*mPoleXZZ)
                       + vectorY.y*(vectorX.z*mPoleXYZ + vectorY.z*mPoleYYZ + vectorZ.z*mPoleYZZ)
                       + vectorZ.y*(vectorX.z*mPoleXZZ + vectorY.z*mPoleYZZ + vectorZ.z*mPoleZZZ);

            labFrameOctopoles[offset+0] = (vectorX.x*T2XXX + vectorY.x*T2YXX + vectorZ.x*T2ZXX);
            labFrameOctopoles[offset+1] = (vectorX.x*T2XXY + vectorY.x*T2YXY + vectorZ.x*T2ZXY);
            labFrameOctopoles[offset+2] = (vectorX.x*T2XXZ + vectorY.x*T2YXZ + vectorZ.x*T2ZXZ);
            labFrameOctopoles[offset+3] = (vectorX.x*T2XYY + vectorY.x*T2YYY + vectorZ.x*T2ZYY);
            labFrameOctopoles[offset+4] = (vectorX.x*T2XYZ + vectorY.x*T2YYZ + vectorZ.x*T2ZYZ);
            labFrameOctopoles[offset+5] = (vectorX.y*T2XYY + vectorY.y*T2YYY + vectorZ.y*T2ZYY);
            labFrameOctopoles[offset+6] = (vectorX.y*T2XYZ + vectorY.y*T2YYZ + vectorZ.y*T2ZYZ);

            // ---------------------------------------------------------------------------------------

            // Now transform the spherical multipoles.  First do the dipoles.

            offset = 3*atom;
            real sphericalDipole[3];
            sphericalDipole[0] = sphericalDipoles[offset];
            sphericalDipole[1] = sphericalDipoles[offset+1];
            sphericalDipole[2] = sphericalDipoles[offset+2];
            if (reverse)
                sphericalDipole[2] *= -1;
            sphericalDipoles[offset] = sphericalDipole[0]*vectorZ.z + sphericalDipole[1]*vectorX.z + sphericalDipole[2]*vectorY.z;
            sphericalDipoles[offset+1] = sphericalDipole[0]*vectorZ.x + sphericalDipole[1]*vectorX.x + sphericalDipole[2]*vectorY.x;
            sphericalDipoles[offset+2] = sphericalDipole[0]*vectorZ.y + sphericalDipole[1]*vectorX.y + sphericalDipole[2]*vectorY.y;


            // Now the quadrupoles.
            offset = 5*atom;
            real sphericalQuadrupole[5];
            sphericalQuadrupole[0] = sphericalQuadrupoles[offset];
            sphericalQuadrupole[1] = sphericalQuadrupoles[offset+1];
            sphericalQuadrupole[2] = sphericalQuadrupoles[offset+2];
            sphericalQuadrupole[3] = sphericalQuadrupoles[offset+3];
            sphericalQuadrupole[4] = sphericalQuadrupoles[offset+4];
            if (reverse) {
                sphericalQuadrupole[2] *= -1;
                sphericalQuadrupole[4] *= -1;
            }
            real rotatedQuadrupole[5] = {0, 0, 0, 0, 0};
            real sqrtThree = SQRT((real) 3);

            rotatedQuadrupole[0] += sphericalQuadrupole[0]*0.5f*(3.0f*vectorZ.z*vectorZ.z - 1.0f) +
                                    sphericalQuadrupole[1]*sqrtThree*vectorZ.z*vectorX.z +
                                    sphericalQuadrupole[2]*sqrtThree*vectorZ.z*vectorY.z +
                                    sphericalQuadrupole[3]*0.5f*sqrtThree*(vectorX.z*vectorX.z - vectorY.z*vectorY.z) +
                                    sphericalQuadrupole[4]*sqrtThree*vectorX.z*vectorY.z;
            rotatedQuadrupole[1] += sphericalQuadrupole[0]*sqrtThree*vectorZ.z*vectorZ.x +
                                    sphericalQuadrupole[1]*(vectorZ.x*vectorX.z + vectorZ.z*vectorX.x) +
                                    sphericalQuadrupole[2]*(vectorZ.x*vectorY.z + vectorZ.z*vectorY.x) +
                                    sphericalQuadrupole[3]*(vectorX.z*vectorX.x - vectorY.z*vectorY.x) +
                                    sphericalQuadrupole[4]*(vectorX.x*vectorY.z + vectorX.z*vectorY.x);
            rotatedQuadrupole[2] += sphericalQuadrupole[0]*sqrtThree*vectorZ.z*vectorZ.y +
                                    sphericalQuadrupole[1]*(vectorZ.y*vectorX.z + vectorZ.z*vectorX.y) +
                                    sphericalQuadrupole[2]*(vectorZ.y*vectorY.z + vectorZ.z*vectorY.y) +
                                    sphericalQuadrupole[3]*(vectorX.z*vectorX.y - vectorY.z*vectorY.y) +
                                    sphericalQuadrupole[4]*(vectorX.y*vectorY.z + vectorX.z*vectorY.y);
            rotatedQuadrupole[3] += sphericalQuadrupole[0]*0.5f*sqrtThree*(vectorZ.x*vectorZ.x - vectorZ.y*vectorZ.y) +
                                    sphericalQuadrupole[1]*(vectorZ.x*vectorX.x - vectorZ.y*vectorX.y) +
                                    sphericalQuadrupole[2]*(vectorZ.x*vectorY.x - vectorZ.y*vectorY.y) +
                                    sphericalQuadrupole[3]*0.5f*(vectorX.x*vectorX.x - vectorX.y*vectorX.y - vectorY.x*vectorY.x + vectorY.y*vectorY.y) +
                                    sphericalQuadrupole[4]*(vectorX.x*vectorY.x - vectorX.y*vectorY.y);
            rotatedQuadrupole[4] += sphericalQuadrupole[0]*sqrtThree*vectorZ.x*vectorZ.y +
                                    sphericalQuadrupole[1]*(vectorZ.y*vectorX.x + vectorZ.x*vectorX.y) +
                                    sphericalQuadrupole[2]*(vectorZ.y*vectorY.x + vectorZ.x*vectorY.y) +
                                    sphericalQuadrupole[3]*(vectorX.x*vectorX.y - vectorY.x*vectorY.y) +
                                    sphericalQuadrupole[4]*(vectorX.y*vectorY.x + vectorX.x*vectorY.y);
            sphericalQuadrupoles[offset] = rotatedQuadrupole[0];
            sphericalQuadrupoles[offset+1] = rotatedQuadrupole[1];
            sphericalQuadrupoles[offset+2] = rotatedQuadrupole[2];
            sphericalQuadrupoles[offset+3] = rotatedQuadrupole[3];
            sphericalQuadrupoles[offset+4] = rotatedQuadrupole[4];

            offset = 7*atom;
            real sphericalOctopole[7];
            sphericalOctopole[0] = sphericalOctopoles[offset+0];
            sphericalOctopole[1] = sphericalOctopoles[offset+1];
            sphericalOctopole[2] = sphericalOctopoles[offset+2];
            sphericalOctopole[3] = sphericalOctopoles[offset+3];
            sphericalOctopole[4] = sphericalOctopoles[offset+4];
            sphericalOctopole[5] = sphericalOctopoles[offset+5];
            sphericalOctopole[6] = sphericalOctopoles[offset+6];
            real rotatedOctopole[7] = {0, 0, 0, 0, 0, 0, 0};
            real sqrtSix = SQRT((real) 6);
            real sqrtTen = SQRT((real) 10);
            real sqrtFifteen = SQRT((real) 15);
            real sqrtThreeHalves = SQRT((real) 1.5f);
            real sqrtFiveHalves = SQRT((real) 2.5f);
            real sqrtTenth = SQRT((real) 0.1f);
            real sqrtFourTenths = SQRT((real) 0.4f);
            real sqrtSixTenths = SQRT((real) 0.6f);

            rotatedOctopole[0] =
                  sphericalOctopole[0]*((-3*vectorX.z*vectorX.z*vectorZ.z)/2 - (3*vectorY.z*vectorY.z*vectorZ.z)/2 + vectorZ.z*vectorZ.z*vectorZ.z)
                + sphericalOctopole[1]*(-(sqrtThreeHalves*vectorX.z*vectorX.z*vectorX.z)/2 - (sqrtThreeHalves*vectorX.z*vectorY.z*vectorY.z)/2  + sqrtSix*vectorX.z*vectorZ.z*vectorZ.z)
                + sphericalOctopole[2]*(-(sqrtThreeHalves*vectorX.z*vectorX.z*vectorY.z)/2 - (sqrtThreeHalves*vectorY.z*vectorY.z*vectorY.z)/2 + sqrtSix*vectorY.z*vectorZ.z*vectorZ.z)
                + sphericalOctopole[3]*((sqrtFifteen*vectorX.z*vectorX.z*vectorZ.z)/2 - (sqrtFifteen*vectorY.z*vectorY.z*vectorZ.z)/2)
                + sqrtFifteen*sphericalOctopole[4]*vectorX.z*vectorY.z*vectorZ.z
                + sphericalOctopole[5]*((sqrtFiveHalves*vectorX.z*vectorX.z*vectorX.z)/2 - (3*sqrtFiveHalves*vectorX.z*vectorY.z*vectorY.z)/2)
                + sphericalOctopole[6]*((3*sqrtFiveHalves*vectorX.z*vectorX.z*vectorY.z)/2 - (sqrtFiveHalves*vectorY.z*vectorY.z*vectorY.z)/2);

            rotatedOctopole[1] =
                  sphericalOctopole[0]*(-(sqrtThreeHalves*vectorX.z*vectorX.z*vectorZ.x)/2 - (sqrtThreeHalves*vectorY.z*vectorY.z*vectorZ.x)/2 - sqrtThreeHalves*vectorX.x*vectorX.z*vectorZ.z - sqrtThreeHalves*vectorY.x*vectorY.z*vectorZ.z + sqrtThreeHalves*vectorZ.x*vectorZ.z*vectorZ.z)
                + sphericalOctopole[1]*((-3*vectorX.x*vectorX.z*vectorX.z)/4 - (vectorX.z*vectorY.x*vectorY.z)/2 - (vectorX.x*vectorY.z*vectorY.z)/4 + 2*vectorX.z*vectorZ.x*vectorZ.z + vectorX.x*vectorZ.z*vectorZ.z)
                + sphericalOctopole[2]*(-(vectorX.z*vectorX.z*vectorY.x)/4 - (vectorX.x*vectorX.z*vectorY.z)/2 - (3*vectorY.x*vectorY.z*vectorY.z)/4 + 2*vectorY.z*vectorZ.x*vectorZ.z + vectorY.x*vectorZ.z*vectorZ.z)
                + sphericalOctopole[3]*((sqrtFiveHalves*vectorX.z*vectorX.z*vectorZ.x)/2 - (sqrtFiveHalves*vectorY.z*vectorY.z*vectorZ.x)/2 + sqrtFiveHalves*vectorX.x*vectorX.z*vectorZ.z - sqrtFiveHalves*vectorY.x*vectorY.z*vectorZ.z)
                + sphericalOctopole[4]*(sqrtFiveHalves*vectorX.z*vectorY.z*vectorZ.x + sqrtFiveHalves*vectorX.z*vectorY.x*vectorZ.z + sqrtFiveHalves*vectorX.x*vectorY.z*vectorZ.z)
                + sphericalOctopole[5]*((sqrtFifteen*vectorX.x*vectorX.z*vectorX.z)/4 - (sqrtFifteen*vectorX.z*vectorY.x*vectorY.z)/2 - (sqrtFifteen*vectorX.x*vectorY.z*vectorY.z)/4)
                + sphericalOctopole[6]*((sqrtFifteen*vectorX.z*vectorX.z*vectorY.x)/4 + (sqrtFifteen*vectorX.x*vectorX.z*vectorY.z)/2 - (sqrtFifteen*vectorY.x*vectorY.z*vectorY.z)/4);

            rotatedOctopole[2] =
                  sphericalOctopole[0]*(-(sqrtThreeHalves*vectorX.z*vectorX.z*vectorZ.y)/2 - (sqrtThreeHalves*vectorY.z*vectorY.z*vectorZ.y)/2 - sqrtThreeHalves*vectorX.y*vectorX.z*vectorZ.z - sqrtThreeHalves*vectorY.y*vectorY.z*vectorZ.z + sqrtThreeHalves*vectorZ.y*vectorZ.z*vectorZ.z)
                + sphericalOctopole[1]*((-3*vectorX.y*vectorX.z*vectorX.z)/4 - (vectorX.z*vectorY.y*vectorY.z)/2 - (vectorX.y*vectorY.z*vectorY.z)/4 + 2*vectorX.z*vectorZ.y*vectorZ.z + vectorX.y*vectorZ.z*vectorZ.z)
                + sphericalOctopole[2]*(-(vectorX.z*vectorX.z*vectorY.y)/4 - (vectorX.y*vectorX.z*vectorY.z)/2 - (3*vectorY.y*vectorY.z*vectorY.z)/4 + 2*vectorY.z*vectorZ.y*vectorZ.z + vectorY.y*vectorZ.z*vectorZ.z)
                + sphericalOctopole[3]*((sqrtFiveHalves*vectorX.z*vectorX.z*vectorZ.y)/2 - (sqrtFiveHalves*vectorY.z*vectorY.z*vectorZ.y)/2 + sqrtFiveHalves*vectorX.y*vectorX.z*vectorZ.z - sqrtFiveHalves*vectorY.y*vectorY.z*vectorZ.z)
                + sphericalOctopole[4]*(sqrtFiveHalves*vectorX.z*vectorY.z*vectorZ.y + sqrtFiveHalves*vectorX.z*vectorY.y*vectorZ.z + sqrtFiveHalves*vectorX.y*vectorY.z*vectorZ.z)
                + sphericalOctopole[5]*((sqrtFifteen*vectorX.y*vectorX.z*vectorX.z)/4 - (sqrtFifteen*vectorX.z*vectorY.y*vectorY.z)/2 - (sqrtFifteen*vectorX.y*vectorY.z*vectorY.z)/4)
                + sphericalOctopole[6]*((sqrtFifteen*vectorX.z*vectorX.z*vectorY.y)/4 + (sqrtFifteen*vectorX.y*vectorX.z*vectorY.z)/2 - (sqrtFifteen*vectorY.y*vectorY.z*vectorY.z)/4);

            rotatedOctopole[3] =
                  sphericalOctopole[0]*(-(sqrtSixTenths*vectorX.x*vectorX.z*vectorZ.x) - sqrtSixTenths*vectorY.x*vectorY.z*vectorZ.x + sqrtSixTenths*vectorX.y*vectorX.z*vectorZ.y + sqrtSixTenths*vectorY.y*vectorY.z*vectorZ.y - (sqrtSixTenths*vectorX.x*vectorX.x*vectorZ.z)/2 + (sqrtSixTenths*vectorX.y*vectorX.y*vectorZ.z)/2 - (sqrtSixTenths*vectorY.x*vectorY.x*vectorZ.z)/2 + (sqrtSixTenths*vectorY.y*vectorY.y*vectorZ.z)/2 + sqrtSixTenths*vectorZ.x*vectorZ.x*vectorZ.z - sqrtSixTenths*vectorZ.y*vectorZ.y*vectorZ.z)
                + sphericalOctopole[1]*((-3*vectorX.x*vectorX.x*vectorX.z)/(2*sqrtTen) + (3*vectorX.y*vectorX.y*vectorX.z)/(2*sqrtTen) - (vectorX.z*vectorY.x*vectorY.x)/(2*sqrtTen) + (vectorX.z*vectorY.y*vectorY.y)/(2*sqrtTen) - (vectorX.x*vectorY.x*vectorY.z)/sqrtTen + (vectorX.y*vectorY.y*vectorY.z)/sqrtTen + sqrtFourTenths*vectorX.z*vectorZ.x*vectorZ.x - sqrtFourTenths*vectorX.z*vectorZ.y*vectorZ.y + 2*sqrtFourTenths*vectorX.x*vectorZ.x*vectorZ.z - 2*sqrtFourTenths*vectorX.y*vectorZ.y*vectorZ.z)
                + sphericalOctopole[2]*(-((vectorX.x*vectorX.z*vectorY.x)/sqrtTen) + (vectorX.y*vectorX.z*vectorY.y)/sqrtTen - (vectorX.x*vectorX.x*vectorY.z)/(2*sqrtTen) + (vectorX.y*vectorX.y*vectorY.z)/(2*sqrtTen) - (3*vectorY.x*vectorY.x*vectorY.z)/(2*sqrtTen) + (3*vectorY.y*vectorY.y*vectorY.z)/(2*sqrtTen) + sqrtFourTenths*vectorY.z*vectorZ.x*vectorZ.x - sqrtFourTenths*vectorY.z*vectorZ.y*vectorZ.y + 2*sqrtFourTenths*vectorY.x*vectorZ.x*vectorZ.z - 2*sqrtFourTenths*vectorY.y*vectorZ.y*vectorZ.z)
                + sphericalOctopole[3]* (vectorX.x*vectorX.z*vectorZ.x - vectorY.x*vectorY.z*vectorZ.x - vectorX.y*vectorX.z*vectorZ.y + vectorY.y*vectorY.z*vectorZ.y + (vectorX.x*vectorX.x*vectorZ.z)/2 - (vectorX.y*vectorX.y*vectorZ.z)/2 - (vectorY.x*vectorY.x*vectorZ.z)/2 + (vectorY.y*vectorY.y*vectorZ.z)/2)
                + sphericalOctopole[4]*(vectorX.z*vectorY.x*vectorZ.x + vectorX.x*vectorY.z*vectorZ.x - vectorX.z*vectorY.y*vectorZ.y - vectorX.y*vectorY.z*vectorZ.y + vectorX.x*vectorY.x*vectorZ.z - vectorX.y*vectorY.y*vectorZ.z)
                + sphericalOctopole[5]* ((sqrtThreeHalves*vectorX.x*vectorX.x*vectorX.z)/2 - (sqrtThreeHalves*vectorX.y*vectorX.y*vectorX.z)/2 - (sqrtThreeHalves*vectorX.z*vectorY.x*vectorY.x)/2 + (sqrtThreeHalves*vectorX.z*vectorY.y*vectorY.y)/2 - sqrtThreeHalves*vectorX.x*vectorY.x*vectorY.z + sqrtThreeHalves*vectorX.y*vectorY.y*vectorY.z)
                + sphericalOctopole[6]*(sqrtThreeHalves*vectorX.x*vectorX.z*vectorY.x - sqrtThreeHalves*vectorX.y*vectorX.z*vectorY.y + (sqrtThreeHalves*vectorX.x*vectorX.x*vectorY.z)/2 - (sqrtThreeHalves*vectorX.y*vectorX.y*vectorY.z)/2 - (sqrtThreeHalves*vectorY.x*vectorY.x*vectorY.z)/2 + (sqrtThreeHalves*vectorY.y*vectorY.y*vectorY.z)/2);

            rotatedOctopole[4] =
                  sphericalOctopole[0]*(-(sqrtSixTenths*vectorX.y*vectorX.z*vectorZ.x) - sqrtSixTenths*vectorY.y*vectorY.z*vectorZ.x - sqrtSixTenths*vectorX.x*vectorX.z*vectorZ.y - sqrtSixTenths*vectorY.x*vectorY.z*vectorZ.y - sqrtSixTenths*vectorX.x*vectorX.y*vectorZ.z - sqrtSixTenths*vectorY.x*vectorY.y*vectorZ.z + 2*sqrtSixTenths*vectorZ.x*vectorZ.y*vectorZ.z)
                + sphericalOctopole[1]*((-3*vectorX.x*vectorX.y*vectorX.z)/sqrtTen - (vectorX.z*vectorY.x*vectorY.y)/sqrtTen - (vectorX.y*vectorY.x*vectorY.z)/sqrtTen - (vectorX.x*vectorY.y*vectorY.z)/sqrtTen + 2*sqrtFourTenths*vectorX.z*vectorZ.x*vectorZ.y + 2*sqrtFourTenths*vectorX.y*vectorZ.x*vectorZ.z + 2*sqrtFourTenths*vectorX.x*vectorZ.y*vectorZ.z)
                + sphericalOctopole[2]*(-((vectorX.y*vectorX.z*vectorY.x)/sqrtTen) - (vectorX.x*vectorX.z*vectorY.y)/sqrtTen - (vectorX.x*vectorX.y*vectorY.z)/sqrtTen - (3*vectorY.x*vectorY.y*vectorY.z)/sqrtTen + 2*sqrtFourTenths*vectorY.z*vectorZ.x*vectorZ.y + 2*sqrtFourTenths*vectorY.y*vectorZ.x*vectorZ.z + 2*sqrtFourTenths*vectorY.x*vectorZ.y*vectorZ.z)
                + sphericalOctopole[3]*(vectorX.y*vectorX.z*vectorZ.x - vectorY.y*vectorY.z*vectorZ.x + vectorX.x*vectorX.z*vectorZ.y - vectorY.x*vectorY.z*vectorZ.y + vectorX.x*vectorX.y*vectorZ.z - vectorY.x*vectorY.y*vectorZ.z)
                + sphericalOctopole[4]*(vectorX.z*vectorY.y*vectorZ.x + vectorX.y*vectorY.z*vectorZ.x + vectorX.z*vectorY.x*vectorZ.y + vectorX.x*vectorY.z*vectorZ.y + vectorX.y*vectorY.x*vectorZ.z + vectorX.x*vectorY.y*vectorZ.z)
                + sphericalOctopole[5]*(sqrtThreeHalves*vectorX.x*vectorX.y*vectorX.z - sqrtThreeHalves*vectorX.z*vectorY.x*vectorY.y - sqrtThreeHalves*vectorX.y*vectorY.x*vectorY.z - sqrtThreeHalves*vectorX.x*vectorY.y*vectorY.z)
                + sphericalOctopole[6]*(sqrtThreeHalves*vectorX.y*vectorX.z*vectorY.x + sqrtThreeHalves*vectorX.x*vectorX.z*vectorY.y + sqrtThreeHalves*vectorX.x*vectorX.y*vectorY.z - sqrtThreeHalves*vectorY.x*vectorY.y*vectorY.z);

            rotatedOctopole[5] =
                  sphericalOctopole[0]*((-3*vectorX.x*vectorX.x*vectorZ.x)/(2*sqrtTen) + (3*vectorX.y*vectorX.y*vectorZ.x)/(2*sqrtTen) - (3*vectorY.x*vectorY.x*vectorZ.x)/(2*sqrtTen) + (3*vectorY.y*vectorY.y*vectorZ.x)/(2*sqrtTen) + vectorZ.x*vectorZ.x*vectorZ.x/sqrtTen + (3*vectorX.x*vectorX.y*vectorZ.y)/sqrtTen + (3*vectorY.x*vectorY.y*vectorZ.y)/sqrtTen - (3*vectorZ.x*vectorZ.y*vectorZ.y)/sqrtTen)
                + sphericalOctopole[1]*(-(sqrtSixTenths*vectorX.x*vectorX.x*vectorX.x)/4 + (3*sqrtSixTenths*vectorX.x*vectorX.y*vectorX.y)/4 - (sqrtSixTenths*vectorX.x*vectorY.x*vectorY.x)/4 + (sqrtSixTenths*vectorX.y*vectorY.x*vectorY.y)/2 + (sqrtSixTenths*vectorX.x*vectorY.y*vectorY.y)/4 + sqrtSixTenths*vectorX.x*vectorZ.x*vectorZ.x - 2*sqrtSixTenths*vectorX.y*vectorZ.x*vectorZ.y - sqrtSixTenths*vectorX.x*vectorZ.y*vectorZ.y)
                + sphericalOctopole[2]*(-(sqrtSixTenths*vectorX.x*vectorX.x*vectorY.x)/4 + (sqrtSixTenths*vectorX.y*vectorX.y*vectorY.x)/4 - (sqrtSixTenths*vectorY.x*vectorY.x*vectorY.x)/4 + (sqrtSixTenths*vectorX.x*vectorX.y*vectorY.y)/2 + (3*sqrtSixTenths*vectorY.x*vectorY.y*vectorY.y)/4 + sqrtSixTenths*vectorY.x*vectorZ.x*vectorZ.x - 2*sqrtSixTenths*vectorY.y*vectorZ.x*vectorZ.y - sqrtSixTenths*vectorY.x*vectorZ.y*vectorZ.y)
                + sphericalOctopole[3]*((sqrtThreeHalves*vectorX.x*vectorX.x*vectorZ.x)/2 - (sqrtThreeHalves*vectorX.y*vectorX.y*vectorZ.x)/2 - (sqrtThreeHalves*vectorY.x*vectorY.x*vectorZ.x)/2 + (sqrtThreeHalves*vectorY.y*vectorY.y*vectorZ.x)/2 - sqrtThreeHalves*vectorX.x*vectorX.y*vectorZ.y + sqrtThreeHalves*vectorY.x*vectorY.y*vectorZ.y)
                + sphericalOctopole[4]*(sqrtThreeHalves*vectorX.x*vectorY.x*vectorZ.x - sqrtThreeHalves*vectorX.y*vectorY.y*vectorZ.x - sqrtThreeHalves*vectorX.y*vectorY.x*vectorZ.y - sqrtThreeHalves*vectorX.x*vectorY.y*vectorZ.y)
                + sphericalOctopole[5]*(vectorX.x*vectorX.x*vectorX.x/4 - (3*vectorX.x*vectorX.y*vectorX.y)/4 - (3*vectorX.x*vectorY.x*vectorY.x)/4 + (3*vectorX.y*vectorY.x*vectorY.y)/2 + (3*vectorX.x*vectorY.y*vectorY.y)/4)
                + sphericalOctopole[6]*((3*vectorX.x*vectorX.x*vectorY.x)/4 - (3*vectorX.y*vectorX.y*vectorY.x)/4 - vectorY.x*vectorY.x*vectorY.x/4 - (3*vectorX.x*vectorX.y*vectorY.y)/2 + (3*vectorY.x*vectorY.y*vectorY.y)/4);

            rotatedOctopole[6] =
                  sphericalOctopole[0]* ((-3*vectorX.x*vectorX.y*vectorZ.x)/sqrtTen - (3*vectorY.x*vectorY.y*vectorZ.x)/sqrtTen - (3*vectorX.x*vectorX.x*vectorZ.y)/(2*sqrtTen) + (3*vectorX.y*vectorX.y*vectorZ.y)/(2*sqrtTen) - (3*vectorY.x*vectorY.x*vectorZ.y)/(2*sqrtTen) + (3*vectorY.y*vectorY.y*vectorZ.y)/(2*sqrtTen) + (3*vectorZ.x*vectorZ.x*vectorZ.y)/sqrtTen - vectorZ.y*vectorZ.y*vectorZ.y/sqrtTen)
                + sphericalOctopole[1]*((-3*sqrtSixTenths*vectorX.x*vectorX.x*vectorX.y)/4 + (sqrtSixTenths*vectorX.y*vectorX.y*vectorX.y)/4 - (sqrtSixTenths*vectorX.y*vectorY.x*vectorY.x)/4 - (sqrtSixTenths*vectorX.x*vectorY.x*vectorY.y)/2 + (sqrtSixTenths*vectorX.y*vectorY.y*vectorY.y)/4 + sqrtSixTenths*vectorX.y*vectorZ.x*vectorZ.x + 2*sqrtSixTenths*vectorX.x*vectorZ.x*vectorZ.y - sqrtSixTenths*vectorX.y*vectorZ.y*vectorZ.y)
                + sphericalOctopole[2]*(-(sqrtSixTenths*vectorX.x*vectorX.y*vectorY.x)/2 - (sqrtSixTenths*vectorX.x*vectorX.x*vectorY.y)/4 + (sqrtSixTenths*vectorX.y*vectorX.y*vectorY.y)/4 - (3*sqrtSixTenths*vectorY.x*vectorY.x*vectorY.y)/4 + (sqrtSixTenths*vectorY.y*vectorY.y*vectorY.y)/4 + sqrtSixTenths*vectorY.y*vectorZ.x*vectorZ.x + 2*sqrtSixTenths*vectorY.x*vectorZ.x*vectorZ.y - sqrtSixTenths*vectorY.y*vectorZ.y*vectorZ.y)
                + sphericalOctopole[3]*(sqrtThreeHalves*vectorX.x*vectorX.y*vectorZ.x - sqrtThreeHalves*vectorY.x*vectorY.y*vectorZ.x + (sqrtThreeHalves*vectorX.x*vectorX.x*vectorZ.y)/2 - (sqrtThreeHalves*vectorX.y*vectorX.y*vectorZ.y)/2 - (sqrtThreeHalves*vectorY.x*vectorY.x*vectorZ.y)/2 + (sqrtThreeHalves*vectorY.y*vectorY.y*vectorZ.y)/2)
                + sphericalOctopole[4]*(sqrtThreeHalves*vectorX.y*vectorY.x*vectorZ.x + sqrtThreeHalves*vectorX.x*vectorY.y*vectorZ.x + sqrtThreeHalves*vectorX.x*vectorY.x*vectorZ.y - sqrtThreeHalves*vectorX.y*vectorY.y*vectorZ.y)
                + sphericalOctopole[5]*((3*vectorX.x*vectorX.x*vectorX.y)/4 - vectorX.y*vectorX.y*vectorX.y/4 - (3*vectorX.y*vectorY.x*vectorY.x)/4 - (3*vectorX.x*vectorY.x*vectorY.y)/2 + (3*vectorX.y*vectorY.y*vectorY.y)/4)
                + sphericalOctopole[6]*((3*vectorX.x*vectorX.y*vectorY.x)/2 + (3*vectorX.x*vectorX.x*vectorY.y)/4 - (3*vectorX.y*vectorX.y*vectorY.y)/4 - (3*vectorY.x*vectorY.x*vectorY.y)/4 + vectorY.y*vectorY.y*vectorY.y/4);

            sphericalOctopoles[offset+0] = rotatedOctopole[0];
            sphericalOctopoles[offset+1] = rotatedOctopole[1];
            sphericalOctopoles[offset+2] = rotatedOctopole[2];
            sphericalOctopoles[offset+3] = rotatedOctopole[3];
            sphericalOctopoles[offset+4] = rotatedOctopole[4];
            sphericalOctopoles[offset+5] = rotatedOctopole[5];
            sphericalOctopoles[offset+6] = rotatedOctopole[6];
        }
        else {
            labFrameDipoles[3*atom] = molecularDipoles[3*atom];
            labFrameDipoles[3*atom+1] = molecularDipoles[3*atom+1];
            labFrameDipoles[3*atom+2] = molecularDipoles[3*atom+2];
            labFrameQuadrupoles[5*atom] = molecularQuadrupoles[5*atom];
            labFrameQuadrupoles[5*atom+1] = molecularQuadrupoles[5*atom+1];
            labFrameQuadrupoles[5*atom+2] = molecularQuadrupoles[5*atom+2];
            labFrameQuadrupoles[5*atom+3] = molecularQuadrupoles[5*atom+3];
            labFrameQuadrupoles[5*atom+4] = molecularQuadrupoles[5*atom+4];
            labFrameOctopoles[7*atom+0] = molecularOctopoles[7*atom+0];
            labFrameOctopoles[7*atom+1] = molecularOctopoles[7*atom+1];
            labFrameOctopoles[7*atom+2] = molecularOctopoles[7*atom+2];
            labFrameOctopoles[7*atom+3] = molecularOctopoles[7*atom+3];
            labFrameOctopoles[7*atom+4] = molecularOctopoles[7*atom+4];
            labFrameOctopoles[7*atom+5] = molecularOctopoles[7*atom+5];
            labFrameOctopoles[7*atom+6] = molecularOctopoles[7*atom+6];
            // qiaozhu added for single ion or axistype=iso/no axistype atom
            labFramePolarizabilities[6*atom+0] = polarizability[3*atom+0];
            labFramePolarizabilities[6*atom+1] = 0.0;
            labFramePolarizabilities[6*atom+2] = 0.0;
            labFramePolarizabilities[6*atom+3] = polarizability[3*atom+1];
            labFramePolarizabilities[6*atom+4] = 0.0;
            labFramePolarizabilities[6*atom+5] = polarizability[3*atom+2];
        }
    }
}

extern "C" __global__ void recordInducedDipoles(const long long* __restrict__ fieldBuffers,
        real* __restrict__ inducedDipole, const real* __restrict__ labFramePolarizabilities) {
    for (int atom = blockIdx.x*blockDim.x+threadIdx.x; atom < NUM_ATOMS; atom += gridDim.x*blockDim.x) {
        real scale = 1/ (real) 0x100000000;
        int offset = 6*atom;
        real3 vx = make_real3(labFramePolarizabilities[offset+0], labFramePolarizabilities[offset+1], labFramePolarizabilities[offset+2]);
        real3 vy = make_real3(labFramePolarizabilities[offset+1], labFramePolarizabilities[offset+3], labFramePolarizabilities[offset+4]);
        real3 vz = make_real3(labFramePolarizabilities[offset+2], labFramePolarizabilities[offset+4], labFramePolarizabilities[offset+5]);
        real3 fld = make_real3(fieldBuffers[atom], fieldBuffers[atom+PADDED_NUM_ATOMS], fieldBuffers[atom+PADDED_NUM_ATOMS*2]) * scale;
        inducedDipole[3*atom+0] = dot(vx, fld);
        inducedDipole[3*atom+1] = dot(vy, fld);
        inducedDipole[3*atom+2] = dot(vz, fld);
    }
}

/**
 * Normalize a vector and return what its magnitude was.
 */
inline __device__ real normVector(real3& v) {
    real n = SQRT(dot(v, v));
    v *= (n > 0 ? RECIP(n) : 0);
    return n;
}

/**
 * Compute the force on each particle due to the torque.
 */
extern "C" __global__ void mapTorqueToForce(unsigned long long* __restrict__ forceBuffers, const long long* __restrict__ torqueBuffers,
        const real4* __restrict__ posq, const int4* __restrict__ multipoleParticles) {
    const int U = 0;
    const int V = 1;
    const int W = 2;
    const int R = 3;
    const int S = 4;
    const int UV = 5;
    const int UW = 6;
    const int VW = 7;
    const int UR = 8;
    const int US = 9;
    const int VS = 10;
    const int WS = 11;
    const int LastVectorIndex = 12;

    const int X = 0;
    const int Y = 1;
    const int Z = 2;
    const int I = 3;

    const real torqueScale = RECIP((double) 0x100000000);

    real3 forces[4];
    real norms[LastVectorIndex];
    real3 vector[LastVectorIndex];
    real angles[LastVectorIndex][2];

    for (int atom = blockIdx.x*blockDim.x + threadIdx.x; atom < NUM_ATOMS; atom += gridDim.x*blockDim.x) {
        int4 particles = multipoleParticles[atom];
        int axisAtom = particles.z;
        int axisType = particles.w;

        // NoAxisType

        if (axisType < 5 && particles.z >= 0) {
            real3 atomPos = trimTo3(posq[atom]);
            vector[U] = atomPos - trimTo3(posq[axisAtom]);
            norms[U] = normVector(vector[U]);
            if (axisType != 4 && particles.x >= 0)
                vector[V] = atomPos - trimTo3(posq[particles.x]);
            else {
                if (fabs(vector[U].x/norms[U]) < 0.866f)
                    vector[V] = make_real3(1, 0, 0);
                else
                    vector[V] = make_real3(0, 1, 0);
            }
            norms[V] = normVector(vector[V]);

            // W = UxV

            if (axisType < 2 || axisType > 3)
                vector[W] = cross(vector[U], vector[V]);
            else
                vector[W] = atomPos - trimTo3(posq[particles.y]);
            norms[W] = normVector(vector[W]);

            vector[UV] = cross(vector[V], vector[U]);
            vector[UW] = cross(vector[W], vector[U]);
            vector[VW] = cross(vector[W], vector[V]);

            norms[UV] = normVector(vector[UV]);
            norms[UW] = normVector(vector[UW]);
            norms[VW] = normVector(vector[VW]);

            angles[UV][0] = dot(vector[U], vector[V]);
            angles[UV][1] = SQRT(1 - angles[UV][0]*angles[UV][0]);

            angles[UW][0] = dot(vector[U], vector[W]);
            angles[UW][1] = SQRT(1 - angles[UW][0]*angles[UW][0]);

            angles[VW][0] = dot(vector[V], vector[W]);
            angles[VW][1] = SQRT(1 - angles[VW][0]*angles[VW][0]);

            real dphi[3];
            real3 torque = make_real3(torqueScale*torqueBuffers[atom], torqueScale*torqueBuffers[atom+PADDED_NUM_ATOMS], torqueScale*torqueBuffers[atom+PADDED_NUM_ATOMS*2]);
            dphi[U] = -dot(vector[U], torque);
            dphi[V] = -dot(vector[V], torque);
            dphi[W] = -dot(vector[W], torque);

            // z-then-x and bisector

            if (axisType == 0 || axisType == 1) {
                real factor1 = dphi[V]/(norms[U]*angles[UV][1]);
                real factor2 = dphi[W]/(norms[U]);
                real factor3 = -dphi[U]/(norms[V]*angles[UV][1]);
                real factor4 = 0;
                if (axisType == 1) {
                    factor2 *= 0.5f;
                    factor4 = 0.5f*dphi[W]/(norms[V]);
                }
                forces[Z] = vector[UV]*factor1 + factor2*vector[UW];
                forces[X] = vector[UV]*factor3 + factor4*vector[VW];
                forces[I] = -(forces[X]+forces[Z]);
                forces[Y] = make_real3(0);
            }
            else if (axisType == 2) {
                // z-bisect

                vector[R] = vector[V] + vector[W];

                vector[S] = cross(vector[U], vector[R]);

                norms[R] = normVector(vector[R]);
                norms[S] = normVector(vector[S]);

                vector[UR] = cross(vector[R], vector[U]);
                vector[US] = cross(vector[S], vector[U]);
                vector[VS] = cross(vector[S], vector[V]);
                vector[WS] = cross(vector[S], vector[W]);

                norms[UR] = normVector(vector[UR]);
                norms[US] = normVector(vector[US]);
                norms[VS] = normVector(vector[VS]);
                norms[WS] = normVector(vector[WS]);

                angles[UR][0] = dot(vector[U], vector[R]);
                angles[UR][1] = SQRT(1 - angles[UR][0]*angles[UR][0]);

                angles[US][0] = dot(vector[U], vector[S]);
                angles[US][1] = SQRT(1 - angles[US][0]*angles[US][0]);

                angles[VS][0] = dot(vector[V], vector[S]);
                angles[VS][1] = SQRT(1 - angles[VS][0]*angles[VS][0]);

                angles[WS][0] = dot(vector[W], vector[S]);
                angles[WS][1] = SQRT(1 - angles[WS][0]*angles[WS][0]);

                real3 t1 = vector[V] - vector[S]*angles[VS][0];
                real3 t2 = vector[W] - vector[S]*angles[WS][0];
                normVector(t1);
                normVector(t2);
                real ut1cos = dot(vector[U], t1);
                real ut1sin = SQRT(1 - ut1cos*ut1cos);
                real ut2cos = dot(vector[U], t2);
                real ut2sin = SQRT(1 - ut2cos*ut2cos);

                real dphiR = -dot(vector[R], torque);
                real dphiS = -dot(vector[S], torque);

                real factor1 = dphiR/(norms[U]*angles[UR][1]);
                real factor2 = dphiS/(norms[U]);
                real factor3 = dphi[U]/(norms[V]*(ut1sin+ut2sin));
                real factor4 = dphi[U]/(norms[W]*(ut1sin+ut2sin));
                forces[Z] = vector[UR]*factor1 + factor2*vector[US];
                forces[X] = (angles[VS][1]*vector[S] - angles[VS][0]*t1)*factor3;
                forces[Y] = (angles[WS][1]*vector[S] - angles[WS][0]*t2)*factor4;
                forces[I] = -(forces[X] + forces[Y] + forces[Z]);
            }
            else if (axisType == 3) {
                // 3-fold

                forces[Z] = (vector[UW]*dphi[W]/(norms[U]*angles[UW][1]) +
                            vector[UV]*dphi[V]/(norms[U]*angles[UV][1]) -
                            vector[UW]*dphi[U]/(norms[U]*angles[UW][1]) -
                            vector[UV]*dphi[U]/(norms[U]*angles[UV][1]))/3;

                forces[X] = (vector[VW]*dphi[W]/(norms[V]*angles[VW][1]) -
                            vector[UV]*dphi[U]/(norms[V]*angles[UV][1]) -
                            vector[VW]*dphi[V]/(norms[V]*angles[VW][1]) +
                            vector[UV]*dphi[V]/(norms[V]*angles[UV][1]))/3;

                forces[Y] = (-vector[UW]*dphi[U]/(norms[W]*angles[UW][1]) -
                            vector[VW]*dphi[V]/(norms[W]*angles[VW][1]) +
                            vector[UW]*dphi[W]/(norms[W]*angles[UW][1]) +
                            vector[VW]*dphi[W]/(norms[W]*angles[VW][1]))/3;
                forces[I] = -(forces[X] + forces[Y] + forces[Z]);
            }
            else if (axisType == 4) {
                // z-only

                forces[Z] = vector[UV]*dphi[V]/(norms[U]*angles[UV][1]) + vector[UW]*dphi[W]/norms[U];
                forces[X] = make_real3(0);
                forces[Y] = make_real3(0);
                forces[I] = -forces[Z];
            }
            else {
                forces[Z] = make_real3(0);
                forces[X] = make_real3(0);
                forces[Y] = make_real3(0);
                forces[I] = make_real3(0);
            }

            // Store results

            atomicAdd(&forceBuffers[particles.z], static_cast<unsigned long long>((long long) (forces[Z].x*0x100000000)));
            atomicAdd(&forceBuffers[particles.z+PADDED_NUM_ATOMS], static_cast<unsigned long long>((long long) (forces[Z].y*0x100000000)));
            atomicAdd(&forceBuffers[particles.z+2*PADDED_NUM_ATOMS], static_cast<unsigned long long>((long long) (forces[Z].z*0x100000000)));
            if (axisType != 4) {
                atomicAdd(&forceBuffers[particles.x], static_cast<unsigned long long>((long long) (forces[X].x*0x100000000)));
                atomicAdd(&forceBuffers[particles.x+PADDED_NUM_ATOMS], static_cast<unsigned long long>((long long) (forces[X].y*0x100000000)));
                atomicAdd(&forceBuffers[particles.x+2*PADDED_NUM_ATOMS], static_cast<unsigned long long>((long long) (forces[X].z*0x100000000)));
            }
            if ((axisType == 2 || axisType == 3) && particles.y > -1) {
                atomicAdd(&forceBuffers[particles.y], static_cast<unsigned long long>((long long) (forces[Y].x*0x100000000)));
                atomicAdd(&forceBuffers[particles.y+PADDED_NUM_ATOMS], static_cast<unsigned long long>((long long) (forces[Y].y*0x100000000)));
                atomicAdd(&forceBuffers[particles.y+2*PADDED_NUM_ATOMS], static_cast<unsigned long long>((long long) (forces[Y].z*0x100000000)));
            }
            atomicAdd(&forceBuffers[atom], static_cast<unsigned long long>((long long) (forces[I].x*0x100000000)));
            atomicAdd(&forceBuffers[atom+PADDED_NUM_ATOMS], static_cast<unsigned long long>((long long) (forces[I].y*0x100000000)));
            atomicAdd(&forceBuffers[atom+2*PADDED_NUM_ATOMS], static_cast<unsigned long long>((long long) (forces[I].z*0x100000000)));
        }
    }
}

/**
 * Compute the electrostatic potential at each of a set of points.
 */
extern "C" __global__ void computePotentialAtPoints(const real4* __restrict__ posq, const real* __restrict__ labFrameDipole,
        const real* __restrict__ labFrameQuadrupole, const real* __restrict__ inducedDipole, const real4* __restrict__ points,
        real* __restrict__ potential, int numPoints, real4 periodicBoxSize, real4 invPeriodicBoxSize, real4 periodicBoxVecX, real4 periodicBoxVecY, real4 periodicBoxVecZ) {
    extern __shared__ real4 localPosq[];
    real3* localDipole = (real3*) &localPosq[blockDim.x];
    real3* localInducedDipole = (real3*) &localDipole[blockDim.x];
    real* localQuadrupole = (real*) &localInducedDipole[blockDim.x];
    for (int basePoint = blockIdx.x*blockDim.x; basePoint < numPoints; basePoint += gridDim.x*blockDim.x) {
        int point = basePoint+threadIdx.x;
        real4 pointPos = points[point];
        real p = 0;
        for (int baseAtom = 0; baseAtom < NUM_ATOMS; baseAtom += blockDim.x) {
            int atom = baseAtom+threadIdx.x;

            // Load data into shared memory.

            if (atom < NUM_ATOMS) {
                localPosq[threadIdx.x] = posq[atom];
                localDipole[threadIdx.x] = make_real3(labFrameDipole[3*atom], labFrameDipole[3*atom+1], labFrameDipole[3*atom+2]);
                localInducedDipole[threadIdx.x] = make_real3(inducedDipole[3*atom], inducedDipole[3*atom+1], inducedDipole[3*atom+2]);
                localQuadrupole[5*threadIdx.x] = labFrameQuadrupole[5*atom];
                localQuadrupole[5*threadIdx.x+1] = labFrameQuadrupole[5*atom+1];
                localQuadrupole[5*threadIdx.x+2] = labFrameQuadrupole[5*atom+2];
                localQuadrupole[5*threadIdx.x+3] = labFrameQuadrupole[5*atom+3];
                localQuadrupole[5*threadIdx.x+4] = labFrameQuadrupole[5*atom+4];
            }
            __syncthreads();

            // Loop over atoms and compute the potential at this point.

            if (point < numPoints) {
                int end = min(blockDim.x, NUM_ATOMS-baseAtom);
                for (int i = 0; i < end; i++) {
                    real3 delta = trimTo3(localPosq[i]-pointPos);
#ifdef USE_PERIODIC
                    APPLY_PERIODIC_TO_DELTA(delta)
#endif
                    real r2 = dot(delta, delta);
                    real rInv = RSQRT(r2);
                    p += localPosq[i].w*rInv;
                    real rr2 = rInv*rInv;
                    real rr3 = rInv*rr2;
                    real scd = dot(localDipole[i], delta);
                    real scu = dot(localInducedDipole[i], delta);
                    p -= (scd+scu)*rr3;
                    real rr5 = 3*rr3*rr2;
                    real scq = delta.x*dot(delta, make_real3(localQuadrupole[5*i+0], localQuadrupole[5*i+1], localQuadrupole[5*i+2])) +
                            delta.y*dot(delta, make_real3(localQuadrupole[5*i+1], localQuadrupole[5*i+3], localQuadrupole[5*i+4])) +
                            delta.z*dot(delta, make_real3(localQuadrupole[5*i+2], localQuadrupole[5*i+4], -localQuadrupole[5*i]-localQuadrupole[5*i+3]));
                    p += scq*rr5;
                }
            }
            __syncthreads();
        }
        potential[point] = p*ENERGY_SCALE_FACTOR;
    }
}
